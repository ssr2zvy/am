#!/bin/sh
# gbuild.sh - Project-specific build script (runs inside container via gu.sh)
# Usage: gbuild.sh [options] [debug|release]
#   --debug          Show full Zig output (don't filter ABI warnings)
#   -m "message"     Git commit message (defaults to timestamp)
#   debug|release    Build mode (default: release)
# Options can appear in any order, interspersed with positional arguments.

set -e

# Parse arguments - options and positionals can be interspersed
SHOW_ALL_OUTPUT=""
GIT_MESSAGE=""
POSITIONALS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            SHOW_ALL_OUTPUT="1"
            shift
            ;;
        -m)
            shift
            GIT_MESSAGE="$1"
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
            POSITIONALS="$POSITIONALS $1"
            shift
            ;;
    esac
done

# Collect remaining args after --
while [ $# -gt 0 ]; do
    POSITIONALS="$POSITIONALS $1"
    shift
done

# Parse positionals: first is build mode
set -- $POSITIONALS
MODE="${1:-release}"

# Validate mode
case "$MODE" in
    debug|release) ;;
    *)
        echo "Invalid mode: $MODE (must be debug or release)" >&2
        exit 1
        ;;
esac

APP_DIR_NAME="am"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}
SHV_PATH="$(am_path container.am.shv)"
# BUILD_PATH is the install destination (was UPA_PATH, now renamed to
# match the host-side directory "build-output/" inside am-mount-host/am/).
BUILD_PATH="$(am_path container.am.build-output)"
GIT_REPO_DIR="$SHV_PATH/src"
ZIG_OUT_BIN="$SHV_PATH/zig-out/bin"

# Zig outputs (built into shv/zig-out/bin/) and install destinations (flat in build-output/).
BUILD_OUTPUT_AM="$ZIG_OUT_BIN/am"
BUILD_OUTPUT_AMCONFIG="$ZIG_OUT_BIN/amconfig"
DEST_AM="$BUILD_PATH/am"
DEST_AMCONFIG="$BUILD_PATH/amconfig"

# Message shown after successful builds
BUILD_SUCCESS_MSG="Build succeeded."

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
    if [ "$MODE" = "debug" ]; then
        zig build
    else
        zig build -Doptimize=ReleaseSafe
    fi
else
    # Normal mode: filter harmless warnings
    ZIG_OUTPUT="$(am_path container.root)/.zig-build-output-$$"
    trap "rm -f $ZIG_OUTPUT" EXIT

    set +e
    if [ "$MODE" = "debug" ]; then
        zig build >"$ZIG_OUTPUT" 2>&1
    else
        zig build -Doptimize=ReleaseSafe >"$ZIG_OUTPUT" 2>&1
    fi
    ZIG_EXIT=$?
    set -e

    grep -v "falling back to default ABI" "$ZIG_OUTPUT" || true
    rm -f "$ZIG_OUTPUT"

    if [ "$ZIG_EXIT" != "0" ]; then
        exit $ZIG_EXIT
    fi
fi

# Copy binaries to upa/ (flat structure)
# Note: viewer.html is embedded in amconfig and extracted at install time
rm -f "$DEST_AM" "$DEST_AMCONFIG"
cp "$BUILD_OUTPUT_AM" "$DEST_AM"
cp "$BUILD_OUTPUT_AMCONFIG" "$DEST_AMCONFIG"

# Auto-commit any changes in the source repo
if [ -d "$GIT_REPO_DIR" ]; then
    cd "$GIT_REPO_DIR" || exit 0
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git init . >/dev/null 2>&1 || true
        git config user.name "am-auto" >/dev/null 2>&1 || true
        git config user.email "am-auto@example.com" >/dev/null 2>&1 || true
    fi
    git add -A >/dev/null 2>&1 || true
    # Use provided message or timestamp
    if [ -n "$GIT_MESSAGE" ]; then
        git commit -m "$GIT_MESSAGE" >/dev/null 2>&1 || true
    else
        git commit -m "$(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1 || true
    fi
fi

echo "$BUILD_SUCCESS_MSG"

