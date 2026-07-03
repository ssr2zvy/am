#!/bin/sh
# image.sh - Sync shared dependencies to container build contexts
# Usage: upaupa image [--debug]
#
# Reads dependencies.txt (pipe-delimited: section|name|path|url|version)
# and copies each file from amupa/upaupaLocal/ into:
#   dev entries -> amdcc build context only
#   app entries -> both amdcc and amc build contexts
#
# Entrypoint scripts are renamed per container:
#   gentrypoint-amdcc.sh -> gentrypoint.sh (in amdcc)
#   gentrypoint-amc.sh  -> gentrypoint.sh (in amc)
#
# image.sh treats every file as opaque bytes and copies byte-for-byte.
# Per-format extraction (unzip / tar / raw cp) lives in the Containerfiles.

_upaupa_image() {
    local debug=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --debug) debug=true; shift ;;
            *) echo "upaupa image: unknown argument: $1" >&2; return 1 ;;
        esac
    done

    local shared="$am_loc/amupa/upaupaLocal"
    local dev_dir="$shared/upaupaDependencies"
    local app_dir="$shared/upaDependencies"
    local dev_manifest="$dev_dir/upaupaDependencies.txt"
    local app_manifest="$app_dir/upaDependencies.txt"
    local amdcc_dest="$amdcc_loc/container-build/amcontainer/upaupaLocal"
    local amc_dest="$amc_loc/amupa/amcontainer/upaupaLocal"

    if [ ! -d "$shared" ]; then
        echo "upaupa image: shared directory not found: $shared" >&2
        return 1
    fi
    for f in "$dev_manifest" "$app_manifest"; do
        if [ ! -f "$f" ]; then
            echo "upaupa image: manifest not found: $f" >&2
            return 1
        fi
    done

    echo "syncing amdcc..."
    mkdir -p "$amdcc_dest"

    echo "syncing amc..."
    mkdir -p "$amc_dest"

    # Helper: copy src to dest only if content differs (or dest missing).
    _sync_file() {
        local src="$1" dst="$2"
        if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
            return 1  # identical, skipped
        fi
        cp -f "$src" "$dst"
        return 0  # copied
    }

    # Sync both manifests so the Containerfile can read them.
    _sync_file "$dev_manifest" "$amdcc_dest/upaupaDependencies.txt"
    _sync_file "$app_manifest" "$amdcc_dest/upaDependencies.txt"
    _sync_file "$app_manifest" "$amc_dest/upaDependencies.txt"

    # Process a manifest file. Args: manifest_path source_dir section_name
    _sync_manifest() {
        local manifest="$1" src_dir="$2" section="$3"

        tr -d '\r' < "$manifest" | while IFS='|' read -r name path url version type format download_format; do
            case "$name" in '#'*|'') continue ;; esac
            [ -z "$path" ] && continue

            # Entrypoint renames
            local amdcc_filename="$path"
            local amc_filename="$path"
            case "$path" in
                gentrypoint-amdcc.sh) amdcc_filename="gentrypoint.sh" ;;
                gentrypoint-amc.sh)  amc_filename="gentrypoint.sh" ;;
            esac

            # All entries go to amdcc (skip amc-only entrypoint)
            if [ -f "$src_dir/$path" ] && [ "$path" != "gentrypoint-amc.sh" ]; then
                if _sync_file "$src_dir/$path" "$amdcc_dest/$amdcc_filename"; then
                    [ "$debug" = true ] && echo "  amdcc: $path -> $amdcc_filename"
                else
                    [ "$debug" = true ] && echo "  amdcc: $amdcc_filename (unchanged)"
                fi
            fi

            # amc gets: all app deps + specific dev deps
            local copy_to_amc=false
            if [ "$section" = "app" ]; then
                copy_to_amc=true
            else
                case "$name" in
                    busybox|ttyd|dtach|vv|run-am|entrypoint-amc|paths) copy_to_amc=true ;;
                esac
            fi

            if [ "$copy_to_amc" = true ] && [ -f "$src_dir/$path" ] && [ "$path" != "gentrypoint-amdcc.sh" ]; then
                if _sync_file "$src_dir/$path" "$amc_dest/$amc_filename"; then
                    [ "$debug" = true ] && echo "  amc:  $path -> $amc_filename"
                else
                    [ "$debug" = true ] && echo "  amc:  $amc_filename (unchanged)"
                fi
            fi
        done
    }

    _sync_manifest "$dev_manifest" "$dev_dir" "dev"
    _sync_manifest "$app_manifest" "$app_dir" "app"

    echo "amdcc synced."
    echo "amc synced."
}
