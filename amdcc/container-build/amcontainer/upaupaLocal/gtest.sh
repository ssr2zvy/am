#!/bin/sh
# gtest.sh - Project-specific test script (runs inside container via gu.sh)
# Usage: gtest.sh [options]
#   --debug    Show full Zig output (don't filter ABI warnings)
# Options can appear in any order.

# Parse arguments
SHOW_ALL_OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            SHOW_ALL_OUTPUT="1"
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

# Clean stale cache if build.zig is newer than .zig-cache
if [ -d "$SHV_PATH/.zig-cache" ] && [ "$SHV_PATH/build.zig" -nt "$SHV_PATH/.zig-cache" ]; then
    rm -rf "$SHV_PATH/.zig-cache" "$SHV_PATH/zig-out"
fi

# Note: "FileNotFound, falling back to default ABI" warnings are harmless.
# They occur because the container doesn't have /usr/lib/libc.so for ABI detection.
# Zig uses sensible defaults and builds correctly. Filter unless --debug.
if [ -n "$SHOW_ALL_OUTPUT" ]; then
    # Debug mode: show all output
    zig build test
else
    # Normal mode: filter harmless warnings
    ZIG_OUTPUT="$(am_path container.root)/.zig-test-output-$$"
    trap "rm -f $ZIG_OUTPUT" EXIT

    set +e
    zig build test >"$ZIG_OUTPUT" 2>&1
    ZIG_EXIT=$?
    set -e

    grep -v "falling back to default ABI" "$ZIG_OUTPUT" || true
    rm -f "$ZIG_OUTPUT"

    if [ "$ZIG_EXIT" != "0" ]; then
        exit $ZIG_EXIT
    fi
fi

