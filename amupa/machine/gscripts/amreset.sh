# amreset - reset container state
# Usage: amreset <amdcc|amc> [options]
#   (no options)   Show usage
#   --binaries     Remove am and amconfig binaries
#   --viewer       Remove viewer.html
#   --amd          Remove vin/ folder (backs up first)
#   --image        Stop container + remove container and builder/final images (keeps base)
#   --all          All of the above
#   --debug        Show verbose output
#
# Usage: amreset --oslf <file>   Convert file to LF (Unix) line endings
# Usage: amreset --oscrlf <file> Convert file to CRLF (Windows) line endings
#   file can be absolute or relative to am_loc

amreset() {
    local debug=false
    local do_binaries=false
    local do_viewer=false
    local do_amd=false
    local do_image=false
    local do_oslf=false
    local do_oscrlf=false
    local positionals=""
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug) debug=true; shift ;;
            --binaries) do_binaries=true; shift ;;
            --viewer) do_viewer=true; shift ;;
            --amd) do_amd=true; shift ;;
            --image) do_image=true; shift ;;
            --all) do_binaries=true; do_viewer=true; do_amd=true; do_image=true; shift ;;
            --oslf) do_oslf=true; shift ;;
            --oscrlf) do_oscrlf=true; shift ;;
            --) shift; break ;;
            -*) echo "amreset: unknown option: $1" >&2; return 1 ;;
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
    
    # Handle --oslf and --oscrlf (line ending conversion)
    if [ "$do_oslf" = true ] || [ "$do_oscrlf" = true ]; then
        local target="${1:-}"
        
        if [ -z "$target" ]; then
            echo "Usage: amreset --oslf <file>"
            echo "       amreset --oscrlf <file>"
            echo "  file can be absolute or relative to am_loc"
            return 1
        fi
        
        # If not absolute, treat as relative to am_loc
        if [ "${target#/}" = "$target" ]; then
            target="$am_loc/$target"
        fi
        
        if [ ! -f "$target" ]; then
            echo "amreset: file not found: $target"
            return 1
        fi
        
        if [ "$do_oslf" = true ]; then
            echo "Converting to LF (Unix) line endings: $target"
            sed -i 's/\r$//' "$target"
        else
            echo "Converting to CRLF (Windows) line endings: $target"
            sed -i 's/$/\r/' "$target"
            # Fix double \r if already had CRLF
            sed -i 's/\r\r$/\r/' "$target"
        fi
        
        echo "amreset: done"
        return 0
    fi
    
    # Container reset mode
    local target="$1"
    shift 2>/dev/null || true
    if [ $# -gt 0 ]; then
        echo "amreset: unexpected argument: $1" >&2
        return 1
    fi
    
    # Validate target
    case "$target" in
        amdcc|amc) ;;
        "")
            echo "Usage: amreset <amdcc|amc> [--binaries] [--viewer] [--amd] [--image] [--all]"
            echo "       amreset --oslf <file>"
            echo "       amreset --oscrlf <file>"
            return 1
            ;;
        *)
            echo "amreset: unknown target: $target (must be amdcc or amc)" >&2
            return 1
            ;;
    esac
    
    # Set paths based on target.
    # amdcc side: am-mount-host/am/build-output/ (host build output, mounted into
    # /container_upa/container_mount/am/build-output inside the dev container).
    # amc side: amcontainer/am/upa/ (where published binaries land for runtime).
    local upa_dir container_name image_name builder_name
    if [ "$target" = "amdcc" ]; then
        upa_dir="$(am_path am.amdcc.build-output.host)"
        container_name="amdcc"
        image_name="amdcc-image"
        builder_name="amdcc-builder"
    else
        upa_dir="$(am_path am.amc.amupa.amcontainer.am.upa)"
        container_name="amc"
        image_name="amc-image"
        builder_name="amc-builder"
    fi
    
    # Check if any action was requested
    if [ "$do_binaries" = false ] && [ "$do_viewer" = false ] && [ "$do_amd" = false ] && [ "$do_image" = false ]; then
        echo "amreset: no action specified"
        echo "Usage: amreset <amdcc|amc> [--binaries] [--viewer] [--amd] [--image] [--all]"
        return 0
    fi
    
    # Remove binaries if requested
    if [ "$do_binaries" = true ]; then
        echo "Removing binaries..."
        if [ -f "$upa_dir/am" ]; then
            rm -f "$upa_dir/am"
            echo "  removed am"
        fi
        if [ -f "$upa_dir/amconfig" ]; then
            rm -f "$upa_dir/amconfig"
            echo "  removed amconfig"
        fi
    fi
    
    # Remove viewer if requested
    if [ "$do_viewer" = true ]; then
        echo "Removing viewer..."
        if [ -f "$upa_dir/viewer.html" ]; then
            rm -f "$upa_dir/viewer.html"
            echo "  removed viewer.html"
        fi
    fi
    
    # Remove vin/ folder if requested (backup first)
    if [ "$do_amd" = true ]; then
        echo "Backing up and removing vin/ folder..."
        _upaupa_vinvin $target --amd 2>/dev/null || echo "  no db files to backup"
        if [ -d "$upa_dir/vin" ]; then
            rm -rf "$upa_dir/vin"
            echo "  removed vin/"
        else
            echo "  vin/ not found"
        fi
    fi
    
    # Remove container and images if requested (must stop first for this operation only)
    if [ "$do_image" = true ]; then
        echo "Stopping $container_name..."
        if podman ps -q -f name=$container_name | grep -q .; then
            if [ "$debug" = true ]; then
                podman stop $container_name
            else
                podman stop $container_name >/dev/null 2>&1
            fi
            echo "  $container_name stopped"
        else
            echo "  $container_name not running"
        fi
        echo "Removing container and images..."
        if [ "$debug" = true ]; then
            podman rm -f $container_name 2>/dev/null && echo "  $container_name container removed"
            podman rmi -f $image_name 2>/dev/null && echo "  $image_name removed"
            podman rmi -f $builder_name 2>/dev/null && echo "  $builder_name removed"
        else
            podman rm -f $container_name >/dev/null 2>&1 && echo "  $container_name container removed"
            podman rmi -f $image_name >/dev/null 2>&1 && echo "  $image_name removed"
            podman rmi -f $builder_name >/dev/null 2>&1 && echo "  $builder_name removed"
        fi
    fi
    
    echo "amreset: done"
}
