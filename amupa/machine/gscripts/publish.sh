# publish - copy from amdcc to amc using tar
# Usage: upaupa publish [--debug] [--build] [all]
#   --debug  Show verbose output
#   --build  Build first, then copy
#   all      Copy binaries + db files

_upaupa_publish() {
    local debug=false
    local do_build=false
    local positionals=""
    
    # Parse arguments - options and positionals can be interspersed
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug) debug=true; shift ;;
            --build) do_build=true; shift ;;
            --) shift; break ;;
            -*) echo "upaupa publish: unknown option: $1" >&2; return 1 ;;
            *) positionals="$positionals $1"; shift ;;
        esac
    done
    
    # Collect remaining args after --
    while [ $# -gt 0 ]; do
        positionals="$positionals $1"
        shift
    done
    
    # Parse positionals
    set -- $positionals
    local mode="$1"
    local src_build
    src_build="$(am_path am.amdcc.build-output.host)"
    local dst_ng
    dst_ng="$(am_path am.amc.amupa.amcontainer.am)"
    local dst_upa="$dst_ng/upa"
    local tar_name="am-release.tar.gz"
    
    # Determine what to copy
    local copy_db=false
    
    case "$mode" in
        "")
            ;;
        all)
            copy_db=true
            ;;
        *)
            echo "Usage: upaupa publish [--debug] [--build] [all]"
            return 1
            ;;
    esac
    
    # Build first if requested
    if [ "$do_build" = true ]; then
        # Stop amc before starting amdcc to avoid port conflicts
        if podman ps -q -f name=amc | grep -q .; then
            echo "stopping amc..."
            podman stop amc >/dev/null 2>&1 || true
            podman rm -f amc >/dev/null 2>&1 || true
        fi

        # Ensure amdcc container is running for the build
        if ! podman ps -q -f name=amdcc | grep -q .; then
            echo "starting amdcc for build..."
            sh "$amdcc_loc/container-build/amcontainer/gcontainer.sh" $( [ "$debug" = true ] && echo "--debug" )
            if [ $? -ne 0 ]; then
                echo "upaupa publish: failed to start amdcc"
                return 1
            fi
        fi

        echo "building..."
        local debug_flag=""
        if [ "$debug" = true ]; then
            debug_flag="--debug"
        fi
        local build_tool
        build_tool="$(am_path am.amupa.upaupaLocal.container-build-tool)"
        sh "$build_tool" --container amdcc $debug_flag test && sh "$build_tool" --container amdcc $debug_flag build
        if [ $? -ne 0 ]; then
            echo "upaupa publish: build failed"
            return 1
        fi

        # Stop amdcc before starting amc to avoid port conflicts
        if podman ps -q -f name=amdcc | grep -q .; then
            echo "stopping amdcc..."
            podman stop amdcc >/dev/null 2>&1 || true
            podman rm -f amdcc >/dev/null 2>&1 || true
        fi
    fi
    
    # Create tar from amdcc upa/ (binaries only, exclude vin/)
    echo "creating tar..."
    local tar_path="$dst_ng/$tar_name"
    # Discover GGUF model files that need to ship alongside the binaries.
    # upa/llama/g.zig (resolveModelPath) loads the model via selfExePath +
    # sibling lookup, so any .gguf in upa/ must be inside the tarball for
    # the runtime image build to find it.
    local gguf_entries=""
    for f in "$src_build"/*.gguf; do
        [ -e "$f" ] || continue
        gguf_entries="$gguf_entries $(basename "$f")"
    done
    if [ -z "$gguf_entries" ]; then
        echo "upaupa publish: WARNING - no .gguf model found in $src_build; am flow will fail at runtime" >&2
    fi
    # Create tar from build output (flat files: am, amconfig, *.gguf).
    # We extract this into amc's upa/ directory directly.
    if [ "$debug" = true ]; then
        tar -czvf "$tar_path" -C "$src_build" am amconfig $gguf_entries
    else
        tar -czf "$tar_path" -C "$src_build" am amconfig $gguf_entries
    fi
    if [ $? -ne 0 ]; then
        echo "upaupa publish: failed to create tar"
        return 1
    fi
    echo "created: $tar_path"
    
    # Remove existing upa/ and extract fresh from tar into upa/
    echo "extracting to host..."
    rm -rf "$dst_upa"
    mkdir -p "$dst_upa"
    if [ "$debug" = true ]; then
        tar -xzvf "$tar_path" -C "$dst_upa"
    else
        tar -xzf "$tar_path" -C "$dst_upa"
    fi
    if [ $? -ne 0 ]; then
        echo "upaupa publish: failed to extract tar"
        return 1
    fi
    
    # Create vin/ directory for sync
    mkdir -p "$dst_upa/vin"
    
    # Rebuild amc image and restart container
    echo "rebuilding amc..."
    local debug_flag=""
    if [ "$debug" = true ]; then
        debug_flag="--debug"
    fi
    sh "$amc_loc/amupa/amcontainer/gcontainer.sh" $debug_flag image
    if [ $? -ne 0 ]; then
        echo "upaupa publish: failed to rebuild amc"
        return 1
    fi
    
    # Copy db if requested
    if [ "$copy_db" = true ]; then
        echo "copying database..."
        if [ "$debug" = true ]; then
            cp -v "$src_build/vin"/*.db "$dst_upa/vin/" 2>/dev/null || true
        else
            cp "$src_build/vin"/*.db "$dst_upa/vin/" 2>/dev/null || true
        fi
    fi
    
    echo "published."
}
