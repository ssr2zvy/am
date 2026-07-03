# amupa - amc container vv commands
# Usage: amupa {am|gn|status|vin}
#   am      Begin am TUI
#   gn      Stop am
#   status  Show status
#   vin     Show URLs

amupa() {
    local vv_script
    vv_script="$(am_path container.gscripts)/vv.sh"
    podman exec amc /bin/sh "$vv_script" "$@"
}
