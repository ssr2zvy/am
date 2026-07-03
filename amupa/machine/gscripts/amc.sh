# amc - container management
# Usage: amc [options] [image]
#   (no args)        Toggle container (begin/stop)
#   image            Rebuild final image only, restart
#   image --builder  Rebuild builder + final
#   image --base     Rebuild base + builder + final
#   --debug          Show verbose output

amc() {
    sh "$amc_loc/amupa/amcontainer/gcontainer.sh" "$@"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "amc: failed (exit $rc). Re-run with --debug for details." >&2
    fi
    return $rc
}
