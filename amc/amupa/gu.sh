#!/bin/bash
# gu.sh - Background sync for amc container (no mount)
# Syncs vin/ between host and container using podman cp
#
# Usage:
#   ./gu.sh          Toggle sync on/off
#   ./gu.sh begin    Start sync
#   ./gu.sh end      Stop sync
#   ./gu.sh status   Show sync status
#
# When sync is running, it copies container→host every few seconds.
# Initial copy-in (host→container) happens when sync starts.
#
# Corruption handling:
#   If .am_corrupt marker detected, sync stops, restores from latest vinvin backup,
#   monitors for 3 minutes, then resumes if stable or disables permanently.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/../../amupa/paths.sh"
if [ ! -f "$PATHS_SH" ]; then
    echo "gu: paths resolver not found at $PATHS_SH" >&2
    exit 1
fi
am_path() {
    sh "$PATHS_SH" "$1"
}
CONTAINER_NAME="amc"
HOST_VIN="$(am_path am.amc.amupa.amcontainer.am.upa)/vin"
CONTAINER_VIN="$(am_path container.am.upa)/vin"
PID_FILE="$SCRIPT_DIR/.gu_sync.pid"
CORRUPT_MARKER="$HOST_VIN/.am_corrupt"
SYNC_DISABLED_FILE="$SCRIPT_DIR/.gu_sync_disabled"
SYNC_INTERVAL=${SYNC_INTERVAL:-3}
RECOVERY_MONITOR_SECS=${RECOVERY_MONITOR_SECS:-180}

# Parse arguments
COMMAND="${1:-toggle}"

is_sync_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

is_container_running() {
    podman ps -q -f name=$CONTAINER_NAME 2>/dev/null | grep -q .
}

sync_in() {
    # Host → Container
    if [ -d "$HOST_VIN" ]; then
        podman cp "$HOST_VIN/." "$CONTAINER_NAME:$CONTAINER_VIN/" 2>/dev/null
    fi
}

sync_out() {
    # Container → Host
    mkdir -p "$HOST_VIN"
    podman cp "$CONTAINER_NAME:$CONTAINER_VIN/." "$HOST_VIN/" 2>/dev/null
}

# Check if corruption marker exists
is_corrupted() {
    [ -f "$CORRUPT_MARKER" ]
}

# Check if sync has been permanently disabled
is_sync_disabled() {
    [ -f "$SYNC_DISABLED_FILE" ]
}

# Restore from vinvin backup
restore_from_backup() {
    # Source ammachine.sh to get the function (if not already sourced)
    if ! type _upaupa_vinvin >/dev/null 2>&1; then
        local ammachine_sh
        ammachine_sh="$(am_path am.amupa.machine.ammachine)"
        . "$ammachine_sh" 2>/dev/null
    fi
    
    # Call vinvin restore (outputs to snapshots/latest)
    if ! _upaupa_vinvin restore amc; then
        echo "gu: restore failed"
        return 1
    fi
    
    # Copy restored files to host vin directory
    local restore_dir
    restore_dir="$(am_path am.amc.vinvin)/snapshots/latest"
    if [ -d "$restore_dir" ]; then
        rm -rf "$HOST_VIN"/*
        cp -r "$restore_dir"/* "$HOST_VIN/" 2>/dev/null || true
        rm -f "$CORRUPT_MARKER"
    fi
    
    # Sync restored files to container
    sync_in
    
    echo "gu: restore synced to container"
    return 0
}

# Handle corruption: stop sync, restore, monitor, resume or disable
handle_corruption() {
    echo "gu: corruption detected, stopping sync"
    
    # Restore from backup
    if ! restore_from_backup; then
        echo "gu: restore failed, disabling sync permanently"
        touch "$SYNC_DISABLED_FILE"
        return 1
    fi
    
    echo "gu: monitoring for $RECOVERY_MONITOR_SECS seconds..."
    
    # Monitor for re-corruption
    local elapsed=0
    while [ $elapsed -lt $RECOVERY_MONITOR_SECS ]; do
        sleep $SYNC_INTERVAL
        elapsed=$((elapsed + SYNC_INTERVAL))
        
        # Continue syncing during monitor period
        if is_container_running; then
            sync_out
        fi
        
        # Check if corruption reappears
        if is_corrupted; then
            echo "gu: corruption reappeared during monitoring"
            echo "gu: disabling sync permanently (re-run service to re-enable)"
            touch "$SYNC_DISABLED_FILE"
            return 1
        fi
    done
    
    echo "gu: recovery successful, resuming normal sync"
    return 0
}


start_sync() {
    if is_sync_running; then
        echo "gu: sync already running"
        return 0
    fi
    
    if is_sync_disabled; then
        echo "gu: sync disabled due to previous corruption"
        echo "gu: remove $SYNC_DISABLED_FILE and restart to re-enable"
        return 1
    fi
    
    if ! is_container_running; then
        echo "gu: container not running"
        return 1
    fi
    
    # Initial copy-in
    sync_in
    
    # Start background sync loop
    (
        while true; do
            # Check for permanent disable
            if is_sync_disabled; then
                echo "gu: sync disabled, exiting"
                break
            fi
            
            if ! is_container_running; then
                break
            fi
            
            # Check for corruption
            if is_corrupted; then
                if ! handle_corruption; then
                    # Recovery failed or re-corrupted, exit loop
                    break
                fi
                # Recovery succeeded, continue loop
            fi
            
            sync_out
            sleep $SYNC_INTERVAL
        done
        rm -f "$PID_FILE"
    ) &
    
    echo $! > "$PID_FILE"
    echo "gu: sync began"
}

stop_sync() {
    if ! is_sync_running; then
        echo "gu: sync not running"
        return 0
    fi
    
    # Final sync out
    if is_container_running; then
        sync_out
    fi
    
    # Stop background process
    kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
    rm -f "$PID_FILE"
    echo "gu: sync stopped"
}

do_status() {
    if is_sync_disabled; then
        echo "gu: sync DISABLED (corruption recovery failed)"
        echo "gu: remove $SYNC_DISABLED_FILE and restart to re-enable"
    elif is_sync_running; then
        echo "gu: sync running (pid $(cat "$PID_FILE"))"
        if is_corrupted; then
            echo "gu: WARNING: corruption marker present"
        fi
    else
        echo "gu: sync not running"
    fi
}

case "$COMMAND" in
    toggle)
        if is_sync_running; then
            stop_sync
        else
            start_sync
        fi
        ;;
    status)
        do_status
        ;;
    begin)
        start_sync
        ;;
    end)
        stop_sync
        ;;
    *)
        echo "Usage: gu.sh [toggle|status|begin|end]"
        exit 1
        ;;
esac
