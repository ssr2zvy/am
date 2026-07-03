#!/bin/sh
# gclean.sh - Project-specific clean script (runs inside container via gu.sh)
# Usage: gclean.sh [options]
#   --debug    Show verbose output
# Options can appear in any order.

set -e

# Parse arguments
DEBUG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            DEBUG="1"
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}
SHV_PATH="$(am_path container.am.shv)"

cd "$SHV_PATH"

if [ -n "$DEBUG" ]; then
    rm -rfv "$SHV_PATH/.zig-cache" "$SHV_PATH/zig-out"
else
    rm -rf "$SHV_PATH/.zig-cache" "$SHV_PATH/zig-out"
fi

