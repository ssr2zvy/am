#!/bin/sh
# Container-side path resolver.
# Usage:
#   sh paths.sh <alias>
#   sh paths.sh --list

set -u

CONTAINER_ROOT="/container_upa"
MOUNT_ROOT="$CONTAINER_ROOT/container_mount"
AM_ROOT="$MOUNT_ROOT/am"

AM_BUILD_OUTPUT_DIR="$AM_ROOT/build-output"

if [ -d "$AM_BUILD_OUTPUT_DIR" ]; then
    AM_BIN_DIR="$AM_BUILD_OUTPUT_DIR"
else
    AM_BIN_DIR="$AM_ROOT/upa"
fi

_emit_alias() {
    case "$1" in
        container.root) printf '%s\n' "$CONTAINER_ROOT" ;;
        container.gscripts) printf '%s\n' "$CONTAINER_ROOT/gscripts" ;;
        container.mount.root) printf '%s\n' "$MOUNT_ROOT" ;;
        container.am.root) printf '%s\n' "$AM_ROOT" ;;
        container.am.shv) printf '%s\n' "$AM_ROOT/shv" ;;
        container.am.build) printf '%s\n' "$AM_BUILD_OUTPUT_DIR" ;;
        container.am.build-output) printf '%s\n' "$AM_BUILD_OUTPUT_DIR" ;;
        container.am.upa) printf '%s\n' "$AM_ROOT/upa" ;;
        container.am.bin.dir) printf '%s\n' "$AM_BIN_DIR" ;;
        container.am.vin) printf '%s\n' "$AM_BIN_DIR/vin" ;;
        container.am.am) printf '%s\n' "$AM_BIN_DIR/am" ;;
        container.am.amconfig) printf '%s\n' "$AM_BIN_DIR/amconfig" ;;
        container.viewer.dir) printf '%s\n' "/tmp/am_viewer" ;;
        container.pid.httpd) printf '%s\n' "$CONTAINER_ROOT/.httpd.pid" ;;
        container.pid.ttyd) printf '%s\n' "$CONTAINER_ROOT/.ttyd.pid" ;;
        container.socket.dtach) printf '%s\n' "$CONTAINER_ROOT/.am.dtach" ;;
        container.lock.am) printf '%s\n' "$AM_BIN_DIR/vin/.am.lock" ;;
        container.run-am) printf '%s\n' "$CONTAINER_ROOT/run-am.sh" ;;
        container.upa.root) printf '%s\n' "$CONTAINER_ROOT/upa" ;;
        container.upa.sqlite_files) printf '%s\n' "$CONTAINER_ROOT/upa/sqlite_files" ;;
        container.upa.llama_files) printf '%s\n' "$CONTAINER_ROOT/upa/llama_files" ;;
        container.upa.model_files) printf '%s\n' "$CONTAINER_ROOT/upa/model_files" ;;
        *)
            echo "paths.sh: unknown alias '$1'" >&2
            return 1
            ;;
    esac
}

_print_aliases() {
    cat << 'EOF'
container.root
container.gscripts
container.mount.root
container.am.root
container.am.shv
container.am.build
container.am.build-output
container.am.upa
container.am.bin.dir
container.am.vin
container.am.am
container.am.amconfig
container.viewer.dir
container.pid.httpd
container.pid.ttyd
container.socket.dtach
container.lock.am
container.run-am
container.upa.root
container.upa.sqlite_files
container.upa.llama_files
container.upa.model_files
EOF
}

if [ "${1:-}" = "--list" ]; then
    _print_aliases
    exit 0
fi

if [ "$#" -lt 1 ]; then
    echo "Usage: sh paths.sh <alias>" >&2
    echo "       sh paths.sh --list" >&2
    exit 1
fi

_emit_alias "$1"
