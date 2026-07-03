#!/bin/sh
# amupa/paths.sh
# Key-based path resolver for host/machine shell scripts.
# Usage:
#   sh paths.sh <alias>
#   sh paths.sh --list

set -u

_self_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

_resolve_am_root() {
    if [ -n "${AM_ROOT_OVERRIDE:-}" ] && [ -d "${AM_ROOT_OVERRIDE}/amupa" ]; then
        printf '%s\n' "$AM_ROOT_OVERRIDE"
        return 0
    fi

    if [ -f "$_self_dir/am_root.path" ]; then
        _hint="$(sed -n '1p' "$_self_dir/am_root.path" | tr -d '\r')"
        if [ -n "$_hint" ] && [ -d "$_hint/amupa" ]; then
            printf '%s\n' "$_hint"
            return 0
        fi
    fi

    if [ "$(basename "$_self_dir")" = "amupa" ]; then
        _parent="$(CDPATH= cd -- "$_self_dir/.." && pwd)"
        if [ -d "$_parent/amupa" ]; then
            printf '%s\n' "$_parent"
            return 0
        fi
    fi

    if [ -d "$_self_dir/../amupa" ]; then
        printf '%s\n' "$(CDPATH= cd -- "$_self_dir/.." && pwd)"
        return 0
    fi

    if [ -d "/mnt/c/users/vin/am/amupa" ]; then
        printf '%s\n' "/mnt/c/users/vin/am"
        return 0
    fi

    return 1
}

AM_ROOT="$(_resolve_am_root)" || {
    echo "paths.sh: unable to resolve am root" >&2
    exit 1
}

_emit_alias() {
    case "$1" in
        am.root) printf '%s\n' "$AM_ROOT" ;;
        am.amupa) printf '%s\n' "$AM_ROOT/amupa" ;;
        am.amupa.paths) printf '%s\n' "$AM_ROOT/amupa/paths.sh" ;;
        am.amupa.machine) printf '%s\n' "$AM_ROOT/amupa/machine" ;;
        am.amupa.machine.ammachine) printf '%s\n' "$AM_ROOT/amupa/machine/ammachine.sh" ;;
        am.amupa.machine.amsetup) printf '%s\n' "$AM_ROOT/amupa/machine/amsetup.sh" ;;
        am.amupa.machine.gscripts) printf '%s\n' "$AM_ROOT/amupa/machine/gscripts" ;;
        am.amupa.upaupa) printf '%s\n' "$AM_ROOT/amupa/upaupa" ;;
        am.amupa.upaupaLocal) printf '%s\n' "$AM_ROOT/amupa/upaupaLocal" ;;
        am.amupa.upaupaLocal.upaupaDependencies) printf '%s\n' "$AM_ROOT/amupa/upaupaLocal/upaupaDependencies" ;;
        am.amupa.vinvin) printf '%s\n' "$AM_ROOT/amupa/vinvin" ;;
        am.machine.home) printf '%s\n' "$HOME/.am" ;;

        am.amc) printf '%s\n' "$AM_ROOT/amc" ;;
        am.amc.amupa) printf '%s\n' "$AM_ROOT/amc/amupa" ;;
        am.amc.amupa.gu) printf '%s\n' "$AM_ROOT/amc/amupa/gu.sh" ;;
        am.amc.amupa.amcontainer) printf '%s\n' "$AM_ROOT/amc/amupa/amcontainer" ;;
        am.amc.amupa.amcontainer.gcontainer) printf '%s\n' "$AM_ROOT/amc/amupa/amcontainer/gcontainer.sh" ;;
        am.amc.amupa.amcontainer.am) printf '%s\n' "$AM_ROOT/amc/amupa/amcontainer/am" ;;
        am.amc.amupa.amcontainer.am.upa) printf '%s\n' "$AM_ROOT/amc/amupa/amcontainer/am/upa" ;;
        am.amc.vinvin) printf '%s\n' "$AM_ROOT/amc/vinvin" ;;

        am.amdcc) printf '%s\n' "$AM_ROOT/amdcc" ;;
        am.amdcc.container-build) printf '%s\n' "$AM_ROOT/amdcc/container-build" ;;
        am.amupa.upaupaLocal.container-build-tool) printf '%s\n' "$AM_ROOT/amupa/upaupaLocal/environmentDependencies/container-build-tool.sh" ;;
        am.amdcc.container-build.amcontainer) printf '%s\n' "$AM_ROOT/amdcc/container-build/amcontainer" ;;
        am.amdcc.container-build.amcontainer.gcontainer) printf '%s\n' "$AM_ROOT/amdcc/container-build/amcontainer/gcontainer.sh" ;;
        am.amdcc.am-mount-host) printf '%s\n' "$AM_ROOT/amdcc/am-mount-host" ;;
        am.amdcc.am-mount-host.am) printf '%s\n' "$AM_ROOT/amdcc/am-mount-host/am" ;;
        am.amdcc.am-mount-host.am.shv) printf '%s\n' "$AM_ROOT/amdcc/am-mount-host/am/shv" ;;
        am.amdcc.build-output.host|amdcc.build-output.host) printf '%s\n' "$AM_ROOT/amdcc/am-mount-host/am/build-output" ;;
        am.amdcc.vinvin) printf '%s\n' "$AM_ROOT/amdcc/vinvin" ;;

        container.root) printf '%s\n' "/container_upa" ;;
        container.gscripts) printf '%s\n' "/container_upa/gscripts" ;;
        container.mount.root) printf '%s\n' "/container_upa/container_mount" ;;
        container.am.root) printf '%s\n' "/container_upa/container_mount/am" ;;
        container.am.shv) printf '%s\n' "/container_upa/container_mount/am/shv" ;;
        container.am.build) printf '%s\n' "/container_upa/container_mount/am/build-output" ;;
        container.am.build-output) printf '%s\n' "/container_upa/container_mount/am/build-output" ;;
        container.am.upa) printf '%s\n' "/container_upa/container_mount/am/upa" ;;
        container.viewer.dir) printf '%s\n' "/tmp/am_viewer" ;;
        container.pid.httpd) printf '%s\n' "/container_upa/.httpd.pid" ;;
        container.pid.ttyd) printf '%s\n' "/container_upa/.ttyd.pid" ;;
        container.socket.dtach) printf '%s\n' "/container_upa/.am.dtach" ;;
        container.run-am) printf '%s\n' "/container_upa/run-am.sh" ;;
        container.upa.root) printf '%s\n' "/container_upa/upa" ;;
        container.upa.sqlite_files) printf '%s\n' "/container_upa/upa/sqlite_files" ;;
        container.upa.llama_files) printf '%s\n' "/container_upa/upa/llama_files" ;;
        container.upa.model_files) printf '%s\n' "/container_upa/upa/model_files" ;;

        *)
            echo "paths.sh: unknown alias '$1'" >&2
            return 1
            ;;
    esac
}

_print_aliases() {
    cat << 'EOF'
am.root
am.amupa
am.amupa.paths
am.amupa.machine
am.amupa.machine.ammachine
am.amupa.machine.amsetup
am.amupa.machine.gscripts
am.amupa.upaupa
am.amupa.upaupaLocal
am.amupa.upaupaLocal.upaupaDependencies
am.amupa.vinvin
am.machine.home
am.amc
am.amc.amupa
am.amc.amupa.gu
am.amc.amupa.amcontainer
am.amc.amupa.amcontainer.gcontainer
am.amc.amupa.amcontainer.am
am.amc.amupa.amcontainer.am.upa
am.amc.vinvin
am.amdcc
am.amdcc.container-build
am.amupa.upaupaLocal.container-build-tool
am.amdcc.container-build.amcontainer
am.amdcc.container-build.amcontainer.gcontainer
am.amdcc.am-mount-host
am.amdcc.am-mount-host.am
am.amdcc.am-mount-host.am.shv
am.amdcc.build-output.host
amdcc.build-output.host
am.amdcc.vinvin
container.root
container.gscripts
container.mount.root
container.am.root
container.am.shv
container.am.build
container.am.build-output
container.am.upa
container.viewer.dir
container.pid.httpd
container.pid.ttyd
container.socket.dtach
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
