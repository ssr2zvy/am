# upaupa - help and command dispatcher
# Usage: upaupa [command]
#   (no args)  Show help
#   publish    Copy amconfig from amdcc to amc
#   vinvin     Backup/restore commands

upaupa() {
    case "$1" in
        image)
            shift
            _upaupa_image "$@"
            ;;
        publish)
            shift
            _upaupa_publish "$@"
            ;;
        vinvin)
            shift
            _upaupa_vinvin "$@"
            ;;
        *)
            _upaupa_help
            ;;
    esac
}

_upaupa_help() {
    echo ""
    echo "am Machine Commands"
    echo "==================="
    echo ""
    echo "=== amdcc (development) ==="
    echo "  amdcc                  Toggle container (begin/stop)"
    echo "  amdcc image            Rebuild final image only, restart"
    echo "  amdcc image --builder  Rebuild builder + final"
    echo "  amdcc image --base     Rebuild base + builder + final"
    echo "  amdccupa               Run tests + release build"
    echo "  amupaupa am            Begin am TUI + viewer"
    echo "  amupaupa gn            Stop services"
    echo "  amupaupa status        Show status (live/partial/not live)"
    echo "  amupaupa vin           Show URLs"
    echo ""
    echo "=== amc (runtime) ==="
    echo "  amc                    Toggle container (begin/stop)"
    echo "  amc image              Rebuild final image only, restart"
    echo "  amc image --builder    Rebuild builder + final"
    echo "  amc image --base       Rebuild base + builder + final"
    echo "  amcupa                 Toggle vin/ sync"
    echo "  amcupa status          Show sync status"
    echo "  amupa am               Begin am TUI"
    echo "  amupa gn               Stop am"
    echo "  amupa status           Show status"
    echo "  amupa vin              Show URLs"
    echo ""
    echo "=== joint ==="
    echo "  upaupa image           Sync shared deps to amdcc + amc build contexts"
    echo "  upaupa vinvin          Toggle background watcher (start/stop) + status"
    echo "  upaupa vinvin stop     Force stop all watchers"
    echo "  upaupa vinvin status   Show watcher status"
    echo "  upaupa vinvin config   Show config (all targets)"
    echo "  upaupa vinvin config <target>   Show config (one target)"
    echo "  upaupa vinvin config --all-on   Enable all targets"
    echo "  upaupa vinvin config --all-off  Disable all targets"
    echo "  upaupa vinvin backup <target> [--verbose]   Manual backup (verbose shows per-file actions)"
    echo "  upaupa vinvin restore <target> [hash]   Restore"
    echo "  upaupa vinvin list <target>     List restore points"
    echo "  upaupa vinvin show <target> [hash] [--full]   Show patch contents"
    echo "  upaupa publish         Copy amconfig amdcc -> amc"
    echo "  upaupa publish --build Build first, then copy amconfig"
    echo "  upaupa publish all     Copy amconfig + db files"
    echo ""
    echo "=== reset ==="
    echo "  amreset <amdcc|amc>              Stop container only"
    echo "  amreset <amdcc|amc> --binaries   Stop + remove am/amconfig"
    echo "  amreset <amdcc|amc> --viewer     Stop + remove viewer.html"
    echo "  amreset <amdcc|amc> --amd        Stop + backup + remove database"
    echo "  amreset <amdcc|amc> --image      Stop + remove container/images"
    echo "  amreset <amdcc|amc> --all        Stop + remove all above"
    echo "  amreset --oslf <file>            Convert file to LF (Unix)"
    echo "  amreset --oscrlf <file>          Convert file to CRLF (Windows)"
    echo ""
echo "=== machine ==="
    echo "  ammachineupa           Apply machine/ changes to WSL + start vinvin watchers"
    echo "  ammachinereset         (alias for ammachineupa)"
    echo "  upaupa                 Show this help"
    echo ""
    echo "See am/amupa/n.md for full documentation"
    echo ""
}
