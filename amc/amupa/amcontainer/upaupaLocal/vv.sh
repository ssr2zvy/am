#!/bin/bash
# vv.sh - Container service control script (shared between amdcc and amc)
# Manages am TUI (via ttyd + dtach) and viewer (via busybox httpd)
#
# State machine:
#   live     = httpd + ttyd running (am/dtach start on-demand when browser connects)
#   partial  = some components running but not all
#   not live = ttyd not running
#
# Commands:
#   am     = ensure live state (idempotent - safe to call multiple times)
#   gn     = ensure not live state (stop everything)
#   status = report current state
#
# Usage:
#   vv.sh [options] {am|gn|status|vin|backup}
# Options:
#   --debug    Show verbose output
# Options can appear in any order, interspersed with positional arguments.

# Paths (mounted source)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}
AM_ROOT="$(am_path container.am.root)"
UPA_DIR="$(am_path container.am.bin.dir)"
AM_BIN="$(am_path container.am.am)"
AMCONFIG_BIN="$(am_path container.am.amconfig)"
DATA_DIR="$(am_path container.am.vin)"
VIEWER_SERVE_DIR="$(am_path container.viewer.dir)"
PORT_TTYD=${PORT_TTYD:-7681}
PORT_VIEWER=${PORT_VIEWER:-8080}
STARTUP_WAIT=${STARTUP_WAIT:-0.5}
TTYD_PID_FILE="$(am_path container.pid.ttyd)"
HTTPD_PID_FILE="$(am_path container.pid.httpd)"
AM_LOCK_FILE="$(am_path container.lock.am)"
DTACH_SOCKET="$(am_path container.socket.dtach)"
RUN_AM_PATH="$(am_path container.run-am)"

# Parse arguments - options and positionals can be interspersed
DEBUG=""
POSITIONALS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            DEBUG=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            # All other args (including --upa) are positional
            POSITIONALS="$POSITIONALS $1"
            shift
            ;;
    esac
done

# Collect remaining args after --
while [ $# -gt 0 ]; do
    POSITIONALS="$POSITIONALS $1"
    shift
done

# Parse positionals
set -- $POSITIONALS
COMMAND="$1"
COMMAND_ARG="$2"

debug_log() {
    [ -n "$DEBUG" ] && echo "$@"
}

# =============================================================================
# Component check functions
# =============================================================================

is_am_running() {
    [ -f "$AM_LOCK_FILE" ] && [ -d "/proc/$(cat "$AM_LOCK_FILE" 2>/dev/null)" ] 2>/dev/null
}

is_dtach_running() {
    # Socket exists and is actually a socket (not stale file)
    [ -S "$DTACH_SOCKET" ]
}

is_ttyd_running() {
    if [ -f "$TTYD_PID_FILE" ]; then
        local pid=$(cat "$TTYD_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
            return 0
        else
            # Stale pid file - clean it up
            rm -f "$TTYD_PID_FILE"
            return 1
        fi
    fi
    return 1
}

is_httpd_running() {
    [ -f "$HTTPD_PID_FILE" ] && [ -d "/proc/$(cat "$HTTPD_PID_FILE" 2>/dev/null)" ] 2>/dev/null
}

# =============================================================================
# State detection
# =============================================================================

get_state() {
    # Live = httpd + ttyd running (am/dtach start on-demand when browser connects)
    # httpd is container lifecycle, always assumed running if container is up
    if is_httpd_running && is_ttyd_running; then
        echo "live"
    elif is_ttyd_running || is_dtach_running || is_am_running; then
        echo "partial"
    else
        echo "not live"
    fi
}

# =============================================================================
# Component start functions
# =============================================================================

# Run amconfig to generate viewer.html (needed before httpd starts)
run_amconfig() {
    if [ -x "$AMCONFIG_BIN" ]; then
        cd "$UPA_DIR"
        if [ -n "$DEBUG" ]; then
            ./amconfig
        else
            ./amconfig >/dev/null 2>&1
        fi
        return $?
    else
        echo "amconfig not found" >&2
        return 1
    fi
}

# Create wrapper script for dtach -A (just runs am)
create_am_wrapper() {
    cat > "$RUN_AM_PATH" << 'WRAPPER'
#!/bin/sh
cd ~
am
WRAPPER
    chmod +x "$RUN_AM_PATH"
}

start_dtach() {
    if is_dtach_running; then
        debug_log "dtach already running"
        return 0
    fi
    
    # Clean up stale state
    pkill -x dtach 2>/dev/null || true
    rm -f "$DTACH_SOCKET"
    
    # Create wrapper script for am
    create_am_wrapper
    
    # Don't start am yet - dtach -c will create session on first attach
    # This ensures am gets proper terminal dimensions from browser
    return 0
}

start_ttyd() {
    if is_ttyd_running; then
        debug_log "ttyd already running"
        return 0
    fi
    
    # Clean up stale state
    rm -f "$TTYD_PID_FILE"
    pkill -x ttyd 2>/dev/null || true
    
    # Ensure dtach master is running first
    start_dtach || return 1
    
    # ttyd creates/attaches to dtach session
    # -W allows client to write (required for input)
    # dtach -c creates session on first connect, -A attaches if exists or creates
    # -r winch sends SIGWINCH on attach for screen redraw
    ttyd -p $PORT_TTYD -W \
        -t fontSize=14 \
        -t fontFamily=monospace \
        -t overlayBg=transparent \
        -t overlayColor=#ffffff \
        -t overlayFont=monospace \
        -t msgClosed='am' \
        -t msgReconnecting='am...' \
        -t msgReconnectPrompt='am' \
        -t msgReconnectedPrompt='' \
        dtach -A "$DTACH_SOCKET" -r winch "$RUN_AM_PATH" >/dev/null 2>&1 &
    echo $! > "$TTYD_PID_FILE"
    
    sleep $STARTUP_WAIT
    is_ttyd_running
}

# =============================================================================
# Component stop functions
# =============================================================================

stop_ttyd() {
    if [ -f "$TTYD_PID_FILE" ]; then
        kill "$(cat "$TTYD_PID_FILE")" 2>/dev/null
    fi
    rm -f "$TTYD_PID_FILE"
    pkill -x ttyd 2>/dev/null || true
}

end_am_session() {
    # Stop am process gracefully
    if [ -f "$AM_LOCK_FILE" ]; then
        local pid=$(cat "$AM_LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
            kill "$pid" 2>/dev/null
            # Wait for graceful shutdown
            for i in 1 2 3 4 5; do
                sleep 1
                [ -d "/proc/$pid" ] || break
            done
            # Force kill if needed
            [ -d "/proc/$pid" ] && kill -9 "$pid" 2>/dev/null
        fi
    fi
    rm -f "$AM_LOCK_FILE"
    
    # Stop dtach
    pkill -x dtach 2>/dev/null || true
    rm -f "$DTACH_SOCKET"
}

# =============================================================================
# Main commands
# =============================================================================

do_ng() {
    local prior_state=$(get_state)
    debug_log "prior state: $prior_state"
    
    case "$prior_state" in
        "live")
            echo "upa: already began"
            return 0
            ;;
        "partial"|"not live")
            # Run amconfig first to generate viewer.html
            run_amconfig || { echo "upa: exception"; return 1; }
            # Update viewer served by httpd (httpd is already running from entrypoint)
            if [ -f "$UPA_DIR/viewer.html" ]; then
                cp "$UPA_DIR/viewer.html" "$VIEWER_SERVE_DIR/index.html" || { echo "upa: exception"; return 1; }
            fi
            # Start ttyd (am starts on-demand when browser connects via dtach -A)
            start_ttyd || { echo "upa: exception"; return 1; }
            
            # Verify we reached live state
            if [ "$(get_state)" = "live" ]; then
                echo "upa: began"
                return 0
            else
                echo "upa: exception"
                return 1
            fi
            ;;
    esac
}

do_gn() {
    local prior_state=$(get_state)
    debug_log "prior state: $prior_state"
    
    case "$prior_state" in
        "not live")
            echo "upa: already stopped"
            return 0
            ;;
        "live"|"partial")
            # Stop ttyd and am (not httpd - it's the container lifecycle)
            stop_ttyd
            end_am_session
            
            echo "upa: stopped"
            return 0
            ;;
    esac
}

do_status() {
    local state=$(get_state)
    echo "upa: $state"
}

do_status_upa() {
    # httpd (container lifecycle - always live if container is running)
    if is_httpd_running; then
        local httpd_pid=$(cat "$HTTPD_PID_FILE" 2>/dev/null)
        echo "httpd: live (pid $httpd_pid)"
    else
        echo "httpd: not live"
    fi
    
    # ttyd
    if is_ttyd_running; then
        local ttyd_pid=$(cat "$TTYD_PID_FILE" 2>/dev/null)
        echo "ttyd: live (pid $ttyd_pid)"
    else
        echo "ttyd: not live"
    fi
    
    # dtach (on-demand - starts when browser connects)
    if is_dtach_running; then
        echo "dtach: live (socket)"
    else
        echo "dtach: not live (on-demand)"
    fi
    
    # am (on-demand - starts when browser connects)
    if is_am_running; then
        local am_pid=$(cat "$AM_LOCK_FILE" 2>/dev/null)
        echo "am: live (pid $am_pid)"
    else
        echo "am: not live (on-demand)"
    fi
}

do_vin() {
    echo "am ttydc: http://localhost:$PORT_TTYD"
    echo "viewer: http://localhost:$PORT_VIEWER"
}

# =============================================================================
# Main
# =============================================================================

case "$COMMAND" in
    am)     do_ng; exit $? ;;
    gn)     do_gn; exit $? ;;
    status)
        if [ "$COMMAND_ARG" = "--upa" ]; then
            do_status_upa; exit 0
        else
            do_status; exit 0
        fi
        ;;
    vin)    do_vin; exit 0 ;;
    *)      echo "Usage: vv.sh [options] {am|gn|status [--upa]|vin}"; exit 1 ;;
esac
