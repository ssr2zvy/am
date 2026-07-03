# amdccupa - build (test + release build)
# Usage: amdccupa [options]
#   --debug        Show all build output
#   -m "message"   Git commit message

amdccupa() {
    local debug_flag=""
    local msg=""
    local positionals=""
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug) debug_flag="--debug"; shift ;;
            -m) shift; msg="$1"; shift ;;
            --) shift; break ;;
            -*) echo "amdccupa: unknown option: $1" >&2; return 1 ;;
            *) positionals="$positionals $1"; shift ;;
        esac
    done
    
    # Collect remaining args after --
    while [ $# -gt 0 ]; do
        positionals="$positionals $1"
        shift
    done
    
    # amdccupa takes no positional arguments
    set -- $positionals
    if [ $# -gt 0 ]; then
        echo "amdccupa: unexpected argument: $1" >&2
        return 1
    fi
    
    local build_tool
    build_tool="$(am_path am.amupa.upaupaLocal.container-build-tool)"
    if [ -n "$msg" ]; then
        sh "$build_tool" --container amdcc $debug_flag test && sh "$build_tool" --container amdcc $debug_flag -m "$msg" build
    else
        sh "$build_tool" --container amdcc $debug_flag test && sh "$build_tool" --container amdcc $debug_flag build
    fi
}
