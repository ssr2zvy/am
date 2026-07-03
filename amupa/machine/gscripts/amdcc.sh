# amdcc - container management
# Usage: amdcc [options] [image]
#   (no args)        Toggle container (begin/stop)
#   image            Rebuild final image only, restart
#   image --builder  Rebuild builder + final
#   image --base     Rebuild base + builder + final
#   --debug          Show verbose output

amdcc() {
    sh "$amdcc_loc/container-build/amcontainer/gcontainer.sh" "$@"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "amdcc: failed (exit $rc). Re-run with --debug for details." >&2
    fi
    return $rc
}
