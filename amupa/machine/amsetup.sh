#!/bin/bash
# amsetup.sh - First-run setup for am machine scripts
# Called by am.ps1 if ~/.am/ammachine.sh doesn't exist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AM_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOST_MACHINE_DIR="$AM_ROOT/amupa/machine"
HOST_PATHS_SH="$AM_ROOT/amupa/paths.sh"

if [ ! -f "$HOME/.am/ammachine.sh" ] || [ ! -f "$HOME/.am/paths.sh" ] || [ ! -d "$HOME/.am/gscripts" ]; then
    if [ ! -f "$HOME/.am/ammachine.sh" ]; then
        echo "am: Setting up machine scripts (first run)..."
    else
        echo "am: Repairing machine scripts..."
    fi
    mkdir -p "$HOME/.am/gscripts"
    cp "$HOST_MACHINE_DIR/ammachine.sh" "$HOME/.am/ammachine.sh"
    cp "$HOST_MACHINE_DIR/gscripts/"*.sh "$HOME/.am/gscripts/"
    cp "$HOST_PATHS_SH" "$HOME/.am/paths.sh"
    printf '%s\n' "$AM_ROOT" > "$HOME/.am/am_root.path"
    chmod 755 "$HOME/.am" "$HOME/.am/gscripts"
    chmod 644 "$HOME/.am/ammachine.sh" "$HOME/.am/gscripts/"*.sh "$HOME/.am/paths.sh" "$HOME/.am/am_root.path"
    sed -i 's/\r$//' "$HOME/.am/ammachine.sh"
    sed -i 's/\r$//' "$HOME/.am/gscripts/"*.sh
    sed -i 's/\r$//' "$HOME/.am/paths.sh"
    if ! grep -q 'source.*\.am/ammachine\.sh' ~/.bashrc 2>/dev/null; then
        echo 'source "$HOME/.am/ammachine.sh"' >> ~/.bashrc
    fi
    echo "am: Setup complete."
fi
source "$HOME/.am/ammachine.sh" && exec bash
