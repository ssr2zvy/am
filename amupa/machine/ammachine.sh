# am machine - bash functions for container management
#
# SETUP: This file is copied to ~/.am/ by the playbook or ammachineupa.
#        It sources all function scripts from gscripts/.
#
# HELP: Run 'upaupa' to see all available commands
#
# DOCS: See am/amupa/n.md for full documentation
#
# Two flows:
#   1. Shell init (bashrc sources this): setup paths, load functions, start vinvin silently
#   2. ammachineupa: sync scripts from host, reload, start vinvin with output

# ============================================================================
# Path setup
# ============================================================================
_ammachine_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$_ammachine_dir/gscripts" ]; then
    _gscripts_dir="$_ammachine_dir/gscripts"
else
    echo "ammachine: gscripts directory not found at $_ammachine_dir/gscripts" >&2
    return 1
fi
if [ -f "$_ammachine_dir/paths.sh" ]; then
    _paths_sh="$_ammachine_dir/paths.sh"
elif [ -f "$_ammachine_dir/../paths.sh" ]; then
    _paths_sh="$_ammachine_dir/../paths.sh"
else
    echo "ammachine: paths resolver not found (expected $_ammachine_dir/paths.sh or $_ammachine_dir/../paths.sh)" >&2
    return 1
fi

am_path() {
    sh "$_paths_sh" "$1"
}

export am_loc="$(am_path am.root)"
export amupa_loc="$(am_path am.amupa)"
export amdcc_loc="$(am_path am.amdcc)"
export amc_loc="$(am_path am.amc)"

# Keep rootless podman/crun runtime state consistent in WSL shells.
# Without this, commands can split across /mnt/wslg/runtime-dir vs /run/user/<uid>,
# which leads to "container ... does not exist" on podman exec/top even while
# podman ps still shows the container.
if [ "$(id -u)" -ne 0 ]; then
    _podman_runtime="/run/user/$(id -u)"
    if [ -d "$_podman_runtime" ] && [ "${XDG_RUNTIME_DIR:-}" != "$_podman_runtime" ]; then
        export XDG_RUNTIME_DIR="$_podman_runtime"
    fi
fi

# ============================================================================
# Source all gscripts
# ============================================================================

for _script in "$_gscripts_dir"/*.sh; do
    if [ -f "$_script" ]; then
        source "$_script"
    fi
done

# ============================================================================
# Shared: start vinvin if inactive
# ============================================================================

_ammachine_ensure_vinvin() {
    local quiet="$1"
    if ! type _vinvin_is_enabled >/dev/null 2>&1; then
        return 0
    fi
    # Start each enabled-but-not-running watcher directly as a child of
    # this shell. The old code backgrounded the entire `upaupa vinvin`
    # call (`upaupa vinvin >/dev/null 2>&1 &`), which made the watcher
    # subshells grandchildren of a transient background job. When that
    # job finished, bash sent SIGHUP to its children (the watchers),
    # killing amdcc and amc instantly. Starting them directly here keeps
    # them as children of the interactive SSH shell, which stays alive.
    local started=0
    for _t in amdcc amc amupa; do
        if _vinvin_is_enabled "$_t" && ! _vinvin_is_running "$_t"; then
            _vinvin_start "$_t"
            started=$((started + 1))
            [ "$quiet" != "quiet" ] && echo "  $_t: started"
        fi
    done
    if [ "$quiet" != "quiet" ]; then
        if [ $started -eq 0 ]; then
            upaupa vinvin status
        fi
    fi
    unset _t
}

# ============================================================================
# ammachineupa: sync scripts from host + reload + start vinvin
# ============================================================================

ammachineupa() {
    local host_machine_dir
    host_machine_dir="$(am_path am.amupa.machine)"
    local host_paths
    host_paths="$(am_path am.amupa.paths)"
    local host_root
    host_root="$(am_path am.root)"
    
    echo "ammachineupa: syncing scripts from host..."
    
    mkdir -p "$HOME/.am/gscripts"
    
    cp "$host_machine_dir/ammachine.sh" "$HOME/.am/ammachine.sh"
    cp "$host_machine_dir/gscripts/"*.sh "$HOME/.am/gscripts/"
    cp "$host_paths" "$HOME/.am/paths.sh"
    printf '%s\n' "$host_root" > "$HOME/.am/am_root.path"
    
    # Fix CRLF -> LF
    sed -i 's/\r$//' "$HOME/.am/ammachine.sh"
    sed -i 's/\r$//' "$HOME/.am/gscripts/"*.sh
    sed -i 's/\r$//' "$HOME/.am/paths.sh"
    
    # Ensure bashrc sources from ~/.am
    if ! grep -q 'source.*\.am/ammachine\.sh' ~/.bashrc 2>/dev/null; then
        sed -i '/source.*amupa.*ammachine\.sh/d' ~/.bashrc 2>/dev/null || true
        echo 'source "$HOME/.am/ammachine.sh"' >> ~/.bashrc
    fi
    
    echo "ammachineupa: reloading..."
    source ~/.bashrc
    
    echo ""
    _ammachine_ensure_vinvin
}

# Alias for backwards compatibility
ammachinereset() {
    ammachineupa "$@"
}

# ============================================================================
# Shell init: start vinvin silently only for interactive shells.
# Non-interactive invocations (e.g. `podman machine ssh <name> bash -lc ...`)
# must not spawn long-lived watcher loops, otherwise the shell never exits.
# ============================================================================

case "$-" in
    *i*) _ammachine_ensure_vinvin quiet ;;
esac

# ============================================================================
# Cleanup
# ============================================================================

unset _ammachine_dir _gscripts_dir _script _podman_runtime
