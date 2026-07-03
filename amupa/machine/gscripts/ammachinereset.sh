# ammachinereset - apply machine/ changes to WSL podman machine
# Usage: ammachinereset
#
# Copies ammachine.sh and gscripts/*.sh from host to WSL machine's ~/.am/
# This allows changes to machine scripts to take effect without recreating the machine.

ammachinereset() {
    local host_machine_dir
    host_machine_dir="$(am_path am.amupa.machine)"
    local host_paths
    host_paths="$(am_path am.amupa.paths)"
    local host_root
    host_root="$(am_path am.root)"
    
    echo "ammachinereset: applying changes from machine/ to WSL..."
    
    # Create ~/.am directory structure
    echo "  Creating directory structure..."
    mkdir -p "$HOME/.am/gscripts"
    
    # Copy ammachine.sh
    echo "  Copying ammachine.sh..."
    cp "$host_machine_dir/ammachine.sh" "$HOME/.am/ammachine.sh"
    cp "$host_paths" "$HOME/.am/paths.sh"
    printf '%s\n' "$host_root" > "$HOME/.am/am_root.path"
    
    # Copy all gscripts
    echo "  Copying gscripts/..."
    cp "$host_machine_dir/gscripts/"*.sh "$HOME/.am/gscripts/"
    
    # Fix line endings (CRLF -> LF)
    echo "  Fixing line endings..."
    sed -i 's/\r$//' "$HOME/.am/ammachine.sh"
    sed -i 's/\r$//' "$HOME/.am/gscripts/"*.sh
    sed -i 's/\r$//' "$HOME/.am/paths.sh"
    
    # Ensure bashrc sources from ~/.am (not /mnt/c)
    if ! grep -q 'source.*\.am/ammachine\.sh' ~/.bashrc 2>/dev/null; then
        echo "  Updating ~/.bashrc..."
        # Remove old source line if present
        sed -i '/source.*amupa.*ammachine\.sh/d' ~/.bashrc 2>/dev/null || true
        # Add new source line
        echo 'source "$HOME/.am/ammachine.sh"' >> ~/.bashrc
    fi
    
    echo "ammachinereset: done"
    echo ""
    echo "reloading shell..."
    source ~/.bashrc
}
