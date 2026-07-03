#!/bin/sh
# gcontainer.sh - Container management for amdcc dev environment
#
# Usage:
#   ./gcontainer.sh [options] [image]
# Options:
#   --debug      Show podman output
#   --base       Rebuild base + builder + final (with image)
#   --builder    Rebuild builder + final (with image)
# Commands:
#   (none)       Toggle: stop if running, start if not
#   image        Rebuild final image, restart container
# Options can appear in any order, interspersed with positional arguments.

# Resolve project root relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/../../../amupa/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}

# Keep rootless podman/crun runtime state consistent in WSL shells.
if [ "$(id -u)" -ne 0 ]; then
    _podman_runtime="/run/user/$(id -u)"
    if [ -d "$_podman_runtime" ] && [ "${XDG_RUNTIME_DIR:-}" != "$_podman_runtime" ]; then
        export XDG_RUNTIME_DIR="$_podman_runtime"
    fi
fi

# The Containerfile reads dependencies.txt directly from the COPY'd
# upaupaLocal/ directory, so no --build-arg forwarding is needed.
# BUILD_ARGS is kept empty for compatibility with the podman build
# invocations below.
BUILD_ARGS=""

# Image and container names
BASE_IMAGE="am-base"
BUILDER_IMAGE="amdcc-builder"
FINAL_IMAGE="amdcc-image"
CONTAINER_NAME="amdcc"

# Container configuration
CONTAINER_DIR="$(am_path am.amdcc.container-build.amcontainer)"
MOUNT_SRC="$(am_path am.amdcc.am-mount-host)"
MOUNT_DST="$(am_path container.mount.root)"

# Port mapping: HOST_PORT:CONTAINER_PORT
# Note: amdcc uses 7682, amc uses 7681 to avoid conflicts
HOST_PORT_TTYD=${HOST_PORT_TTYD:-7682}
CONTAINER_PORT_TTYD=${CONTAINER_PORT_TTYD:-7681}
HOST_PORT_VIEWER=${HOST_PORT_VIEWER:-8080}
CONTAINER_PORT_VIEWER=${CONTAINER_PORT_VIEWER:-8080}

# Parse arguments - options and positionals can be interspersed
DEBUG=false
REBUILD_FLAG=""
POSITIONALS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            DEBUG=true
            shift
            ;;
        --base)
            REBUILD_FLAG="--base"
            shift
            ;;
        --builder)
            REBUILD_FLAG="--builder"
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

# Parse positionals: first is mode
set -- $POSITIONALS
MODE="${1:-toggle}"

# Function: Stop and remove container if exists
stop_container() {
    if podman ps -q -f name=$CONTAINER_NAME | grep -q .; then
        echo "Stopping container..."
        if [ "$DEBUG" = true ]; then
            podman stop $CONTAINER_NAME || true
        else
            podman stop $CONTAINER_NAME >/dev/null 2>&1 || true
        fi
    fi
    if podman container exists $CONTAINER_NAME 2>/dev/null; then
        if [ "$DEBUG" = true ]; then
            podman rm -f $CONTAINER_NAME || true
        else
            podman rm -f $CONTAINER_NAME >/dev/null 2>&1 || true
        fi
    fi
}

# Function: Start container
#
# --memory 6g caps the dev container at 6 GiB so the Zig compile and the
# llama.cpp working set for `am flow` cannot squeeze each other (or the
# sibling amc container) out of the 8 GiB VM. The VM-level allocation
# is set by `podman machine init --memory 8192 --cpus 4` in
# amupa/upaupa/am-pm.ps1 and am-u.ps1.
start_container() {
    echo "Beginning container..."
    
    # Pass DEBUG env var to container if debug mode is enabled
    # Note: In DEBUG mode, don't use --rm so container stays for log inspection
    if [ "$DEBUG" = true ]; then
        CONTAINER_ID=$(podman run --pull=never -d --name $CONTAINER_NAME \
            --memory 6g \
            -p $HOST_PORT_TTYD:$CONTAINER_PORT_TTYD \
            -p $HOST_PORT_VIEWER:$CONTAINER_PORT_VIEWER \
            -v "$MOUNT_SRC:$MOUNT_DST" \
            -e DEBUG=1 \
            -e PORT_TTYD=$CONTAINER_PORT_TTYD \
            -e PORT_VIEWER=$CONTAINER_PORT_VIEWER \
            -e HOST_PORT_TTYD=$HOST_PORT_TTYD \
            -e HOST_PORT_VIEWER=$HOST_PORT_VIEWER \
            $FINAL_IMAGE)
    else
        CONTAINER_ID=$(podman run --pull=never -d --rm --name $CONTAINER_NAME \
            --memory 6g \
            -p $HOST_PORT_TTYD:$CONTAINER_PORT_TTYD \
            -p $HOST_PORT_VIEWER:$CONTAINER_PORT_VIEWER \
            -v "$MOUNT_SRC:$MOUNT_DST" \
            -e PORT_TTYD=$CONTAINER_PORT_TTYD \
            -e PORT_VIEWER=$CONTAINER_PORT_VIEWER \
            -e HOST_PORT_TTYD=$HOST_PORT_TTYD \
            -e HOST_PORT_VIEWER=$HOST_PORT_VIEWER \
            $FINAL_IMAGE)
    fi
    
    if [ $? -eq 0 ]; then
        # Wait a few seconds and verify container is still running
        sleep 3
        if podman ps -q -f name=$CONTAINER_NAME | grep -q .; then
            echo "Container began successfully."
        else
            echo "Container began but crashed immediately."
            echo "Last logs:"
            podman logs $CONTAINER_ID 2>&1 || echo "(Container already removed, logs unavailable)"
            exit 1
        fi
    else
        echo "Failed to begin container."
        exit 1
    fi
}

# Function: Run a podman build quietly but show errors on failure.
# In non-debug mode, output is captured to a temp file; on failure the
# last 30 lines are printed so the user can see WHAT failed without
# needing to re-run with --debug.
quiet_build() {
    local log
    log=$(mktemp /tmp/ambuild.XXXXXX)
    if podman "$@" >"$log" 2>&1; then
        rm -f "$log"
        return 0
    else
        echo "Build failed. Last 30 lines of output:" >&2
        tail -30 "$log" >&2
        rm -f "$log"
        return 1
    fi
}

# Function: Prune dangling images (cleanup after builds)
prune_images() {
    podman image prune -f >/dev/null 2>&1 || true
}

# Mode: image (rebuild images)
if [ "$MODE" = "image" ]; then
    stop_container

    # Determine what to rebuild based on flags
    # All image rebuilds use --no-cache to ensure upaupaLocal changes are picked up
    if [ "$REBUILD_FLAG" = "--base" ]; then
        # Rebuild everything from base
        echo "Rebuilding base image: $BASE_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build --no-cache -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build --no-cache -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
        fi
        
        echo "Rebuilding builder stage: $BUILDER_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
        
        echo "Rebuilding final image: $FINAL_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
    
    elif [ "$REBUILD_FLAG" = "--builder" ]; then
        # Rebuild builder + final (use cached base)
        echo "Rebuilding builder stage: $BUILDER_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
        
        echo "Rebuilding final image: $FINAL_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
    
    else
        # Default: rebuild final only (use cached base + builder)
        # Ensure base exists
        if ! podman image exists $BASE_IMAGE; then
            echo "Base image not found. Building $BASE_IMAGE..."
            if [ "$DEBUG" = true ]; then
                podman build --no-cache -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
            else
                quiet_build build --no-cache -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
            fi
        fi
        
        # Ensure builder exists
        if ! podman image exists $BUILDER_IMAGE; then
            echo "Builder image not found. Building $BUILDER_IMAGE..."
            if [ "$DEBUG" = true ]; then
                podman build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
            else
                quiet_build build $BUILD_ARGS --pull=never --no-cache --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
            fi
        fi
        
        echo "Rebuilding final image: $FINAL_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never --no-cache -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
    fi

    # Prune dangling images after rebuild
    prune_images

    start_container
    exit 0
fi

# Mode: toggle (default)
if podman ps -q -f name=$CONTAINER_NAME | grep -q .; then
    echo "Container running. Stopping..."
    stop_container
    echo "Done."
else
    # Ensure images exist before starting
    if ! podman image exists $FINAL_IMAGE; then
        echo "Final image not found. Building images..."
        
        if ! podman image exists $BASE_IMAGE; then
            echo "Building base image: $BASE_IMAGE"
            if [ "$DEBUG" = true ]; then
                podman build -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
            else
                quiet_build build -t $BASE_IMAGE -f "$CONTAINER_DIR/baseContainerfile" "$CONTAINER_DIR" || exit 1
            fi
        fi
        
        if ! podman image exists $BUILDER_IMAGE; then
            echo "Building builder stage: $BUILDER_IMAGE"
            if [ "$DEBUG" = true ]; then
                podman build $BUILD_ARGS --pull=never --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
            else
                quiet_build build $BUILD_ARGS --pull=never --target builder -t $BUILDER_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
            fi
        fi
        
        echo "Building final image: $FINAL_IMAGE"
        if [ "$DEBUG" = true ]; then
            podman build $BUILD_ARGS --pull=never -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        else
            quiet_build build $BUILD_ARGS --pull=never -t $FINAL_IMAGE -f "$CONTAINER_DIR/Containerfile" "$CONTAINER_DIR" || exit 1
        fi
    fi
    
    start_container
fi
