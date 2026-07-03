#!/bin/sh
# container-build-tool.sh - Run Zig commands inside a running dev container
# (formerly amdcc/container-build/gu.sh; relocated here as an
# environmentDependency - host-side only, never baked into any container
# image, since its `podman exec` logic can't run from inside the container
# it targets.)
# Usage: container-build-tool.sh [options] --container <name> {test|compile|build|clean}
# Options:
#   --container <name>  Name of the running container to exec into (required)
#   --debug              Show all build output including harmless warnings
#   -m "message"         Git commit message for build (passed to gbuild.sh)
# Options can appear in any order, interspersed with positional arguments.

# Parse arguments - options and positionals can be interspersed
DEBUG_FLAG=""
MESSAGE=""
CONTAINER_NAME=""
POSITIONALS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --container)
            shift
            CONTAINER_NAME="$1"
            shift
            ;;
        --debug)
            DEBUG_FLAG="--debug"
            shift
            ;;
        -m)
            shift
            MESSAGE="$1"
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

if [ -z "$CONTAINER_NAME" ]; then
    echo "container-build-tool: --container <name> is required" >&2
    exit 1
fi

# Parse positionals: first is command
set -- $POSITIONALS
COMMAND="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/../../paths.sh"
if [ ! -f "$PATHS_SH" ]; then
    echo "container-build-tool: paths resolver not found at $PATHS_SH" >&2
    exit 1
fi
am_path() {
    sh "$PATHS_SH" "$1"
}

# Paths inside the container
# Build scripts are provisioned via upaupaDependencies and placed in
# /container_upa/gscripts during image build.
APP_SCRIPT_DIR="$(am_path container.gscripts)"
VV_SCRIPT="$APP_SCRIPT_DIR/vv.sh"
BUILD_SCRIPT="$APP_SCRIPT_DIR/gbuild.sh"
TEST_SCRIPT="$APP_SCRIPT_DIR/gtest.sh"
CLEAN_SCRIPT="$APP_SCRIPT_DIR/gclean.sh"
SHV_PATH="$(am_path container.am.shv)"

# Check if container is running
if ! podman ps -q -f name=$CONTAINER_NAME | grep -q .; then
    echo "Error: Container '$CONTAINER_NAME' is not running."
    echo "Run gcontainer.sh first to begin the container."
    exit 1
fi

# Clean stale cache if build.zig is newer than cache (used by test-only path)
clean_if_stale() {
    podman exec $CONTAINER_NAME sh -c "
        if [ -d $SHV_PATH/.zig-cache ]; then
            if [ $SHV_PATH/build.zig -nt $SHV_PATH/.zig-cache ]; then
                rm -rf $SHV_PATH/.zig-cache $SHV_PATH/zig-out
            fi
        fi
    "
}

case "$COMMAND" in
    test)
        # Check if services are running, stop only if needed
        STATUS=$(podman exec $CONTAINER_NAME "$VV_SCRIPT" status 2>/dev/null || echo "upa: not live")
        if echo "$STATUS" | grep -q "upa: live"; then
            echo "Stopping services..."
            podman exec $CONTAINER_NAME "$VV_SCRIPT" gn >/dev/null 2>&1
        fi
        
        echo "Running tests..."
        clean_if_stale
        if podman exec $CONTAINER_NAME sh "$TEST_SCRIPT" $DEBUG_FLAG; then
            echo "Tests passed."
        else
            echo "Tests failed."
            exit 1
        fi
        ;;
    compile)
        # Check if services are running, stop only if needed
        STATUS=$(podman exec $CONTAINER_NAME "$VV_SCRIPT" status 2>/dev/null || echo "upa: not live")
        if echo "$STATUS" | grep -q "upa: live"; then
            echo "Stopping services..."
            podman exec $CONTAINER_NAME "$VV_SCRIPT" gn >/dev/null 2>&1
        fi
        
        echo "Compiling (debug)..."
        if podman exec $CONTAINER_NAME sh "$BUILD_SCRIPT" debug $DEBUG_FLAG; then
            :
        else
            echo "Build failed."
            exit 1
        fi
        ;;
    build)
        # Check if services are running, stop only if needed
        STATUS=$(podman exec $CONTAINER_NAME "$VV_SCRIPT" status 2>/dev/null || echo "upa: not live")
        if echo "$STATUS" | grep -q "upa: live"; then
            echo "Stopping services..."
            podman exec $CONTAINER_NAME "$VV_SCRIPT" gn >/dev/null 2>&1
        fi
        
        echo "Building (release)..."
        if [ -n "$MESSAGE" ]; then
            if podman exec $CONTAINER_NAME sh "$BUILD_SCRIPT" $DEBUG_FLAG -m "$MESSAGE" release; then
                :
            else
                echo "Build failed."
                exit 1
            fi
        else
            if podman exec $CONTAINER_NAME sh "$BUILD_SCRIPT" $DEBUG_FLAG release; then
                :
            else
                echo "Build failed."
                exit 1
            fi
        fi
        ;;
    clean)
        echo "Cleaning build artifacts..."
        if podman exec $CONTAINER_NAME sh "$CLEAN_SCRIPT" $DEBUG_FLAG; then
            echo "Done."
        else
            echo "Clean failed."
            exit 1
        fi
        ;;
    *)
        echo "Usage: container-build-tool.sh [options] --container <name> {test|compile|build|clean}"
        echo "Options:"
        echo "  --container <name> - name of the running container to exec into (required)"
        echo "  --debug             - show all output including harmless warnings"
        echo "  -m \"message\"        - git commit message (build only, default: timestamp)"
        echo "Commands:"
        echo "  test           - run unit tests"
        echo "  compile        - debug build"
        echo "  build          - release build"
        echo "  clean          - remove .zig-cache and zig-out"
        exit 1
        ;;
esac
