# amupaupa - amdcc container vv commands
# Usage: amupaupa {am|gn|status|vin}
#   am      Begin am TUI + viewer
#   gn      Stop services
#   status  Show status (live/partial/not live)
#   vin     Show URLs

amupaupa() {
    local vv_script
    local runtime_dir
    vv_script="$(am_path container.gscripts)/vv.sh"
    runtime_dir="/run/user/$(id -u)"

    if [ -d "$runtime_dir" ]; then
        XDG_RUNTIME_DIR="$runtime_dir" podman exec amdcc /bin/sh "$vv_script" "$@"
    else
        podman exec amdcc /bin/sh "$vv_script" "$@"
    fi
}
