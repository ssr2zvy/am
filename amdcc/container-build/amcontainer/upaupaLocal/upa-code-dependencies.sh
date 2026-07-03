#!/bin/sh
# upa-code-dependencies.sh - Copy vendored dependencies to mounted path
# Runs once at container startup before serve-tui.sh
# Exit immediately on any error (unless DEBUG=1)
if [ "$DEBUG" != "1" ]; then
    set -e
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}

AM_ROOT="$(am_path container.am.root)"
SQLITE_SRC="$(am_path container.upa.sqlite_files)"
SQLITE_BASE="$AM_ROOT/shv/upaupa/sqlite"
SQLITE_SRC_DEST="$SQLITE_BASE/src"

# llama.cpp + GGUF model paths (mirror of the SQLite layout above).
# llama_files/{include,src,ggml} → shv/upaupa/llama/{include,src,ggml}
# model_files/am-model.gguf → upa/am-model.gguf (sibling of the runnable am
#   binary). publish.sh reads from this same upa/ folder, so staging the
#   model here means both dev runs and `upaupa publish` find it.
LLAMA_SRC="$(am_path container.upa.llama_files)"
LLAMA_BASE="$AM_ROOT/shv/upaupa/llama"
LLAMA_INCLUDE_DEST="$LLAMA_BASE/include"
LLAMA_SRC_DEST="$LLAMA_BASE/src"
LLAMA_GGML_DEST="$LLAMA_BASE/ggml"
MODEL_SRC_DIR="$(am_path container.upa.model_files)"
MODEL_DEST_DIR="$(am_path container.am.upa)"
MODEL_FILENAME="am-model.gguf"

echo "[$(date '+%H:%M:%S')] Beginning dependency setup..."

# Verify source files exist in image
if [ ! -d "$SQLITE_SRC" ]; then
    echo "[$(date '+%H:%M:%S')] ERROR: SQLite source directory not found at $SQLITE_SRC"
    exit 1
fi

if [ ! -f "$SQLITE_SRC/sqlite3.c" ]; then
    echo "[$(date '+%H:%M:%S')] ERROR: sqlite3.c not found at $SQLITE_SRC"
    exit 1
fi

# Copy sqlite files from image to mounted path if not already there
if [ ! -f "$SQLITE_SRC_DEST/sqlite3.c" ]; then
    echo "[$(date '+%H:%M:%S')] Copying sqlite files to mounted path..."
    
    # Create base directory
    mkdir -p "$SQLITE_BASE" || { echo "ERROR: Failed to create $SQLITE_BASE"; exit 1; }
    
    # Copy zip if it exists
    if ls "$SQLITE_SRC"/*.zip >/dev/null 2>&1; then
        cp -f "$SQLITE_SRC"/*.zip "$SQLITE_BASE/" 2>/dev/null || true
        echo "[$(date '+%H:%M:%S')] SQLite zip copied to $SQLITE_BASE"
    fi
    
    # Copy extracted source files to src/ subdirectory
    mkdir -p "$SQLITE_SRC_DEST" || { echo "ERROR: Failed to create $SQLITE_SRC_DEST"; exit 1; }
    cp -f "$SQLITE_SRC"/sqlite3.c "$SQLITE_SRC"/sqlite3.h "$SQLITE_SRC"/sqlite3ext.h "$SQLITE_SRC_DEST/" || { echo "ERROR: Failed to copy sqlite source files"; exit 1; }
    echo "[$(date '+%H:%M:%S')] SQLite source files ready at $SQLITE_SRC_DEST"
else
    echo "[$(date '+%H:%M:%S')] SQLite files already present in mounted path."
fi

# Verify llama.cpp sources exist in image. Unlike SQLite, the build hard-fails
# without them (the static llama_lib in build.zig references the .c/.cpp
# files by name), so we treat a missing tree as a fatal install error.
if [ ! -d "$LLAMA_SRC" ]; then
    echo "[$(date '+%H:%M:%S')] ERROR: llama.cpp source directory not found at $LLAMA_SRC"
    exit 1
fi
if [ ! -f "$LLAMA_SRC/include/llama.h" ]; then
    echo "[$(date '+%H:%M:%S')] ERROR: llama.h not found at $LLAMA_SRC/include/"
    exit 1
fi
if [ ! -d "$LLAMA_SRC/ggml" ]; then
    echo "[$(date '+%H:%M:%S')] ERROR: ggml directory not found at $LLAMA_SRC/ggml/"
    exit 1
fi

# Sync llama.cpp include/, src/, and ggml/ trees into the mounted
# shv/upaupa/llama/ tree. Idempotent: only runs the copy when llama.h
# is missing in the destination. Uses cp -r for the whole subdirectories
# so new/renamed files in future releases are picked up automatically.
if [ ! -f "$LLAMA_INCLUDE_DEST/llama.h" ]; then
    echo "[$(date '+%H:%M:%S')] Copying llama.cpp files to mounted path..."
    mkdir -p "$LLAMA_INCLUDE_DEST" "$LLAMA_SRC_DEST" "$LLAMA_GGML_DEST" || { echo "ERROR: Failed to create $LLAMA_BASE"; exit 1; }
    cp -rf "$LLAMA_SRC/include/." "$LLAMA_INCLUDE_DEST/" || { echo "ERROR: Failed to copy llama headers"; exit 1; }
    cp -rf "$LLAMA_SRC/src/."     "$LLAMA_SRC_DEST/"     || { echo "ERROR: Failed to copy llama sources"; exit 1; }
    cp -rf "$LLAMA_SRC/ggml/."    "$LLAMA_GGML_DEST/"    || { echo "ERROR: Failed to copy ggml tree"; exit 1; }
    echo "[$(date '+%H:%M:%S')] llama.cpp files ready at $LLAMA_BASE"
else
    echo "[$(date '+%H:%M:%S')] llama.cpp files already present in mounted path."
fi

# Stage the GGUF model next to the runnable `am` binary. resolveModelPath()
# in upa/llama/g.zig looks for the file via selfExePath sibling lookup, so it
# must live in the same upa/ folder that holds the dev binary (and that
# publish.sh later tars up for the runtime image).
if [ -f "$MODEL_SRC_DIR/$MODEL_FILENAME" ]; then
    if [ ! -f "$MODEL_DEST_DIR/$MODEL_FILENAME" ]; then
        echo "[$(date '+%H:%M:%S')] Copying GGUF model to mounted path..."
        mkdir -p "$MODEL_DEST_DIR" || { echo "ERROR: Failed to create $MODEL_DEST_DIR"; exit 1; }
        cp -f "$MODEL_SRC_DIR/$MODEL_FILENAME" "$MODEL_DEST_DIR/$MODEL_FILENAME" || { echo "ERROR: Failed to copy GGUF model"; exit 1; }
        echo "[$(date '+%H:%M:%S')] GGUF model ready at $MODEL_DEST_DIR/$MODEL_FILENAME"
    else
        echo "[$(date '+%H:%M:%S')] GGUF model already present in mounted path."
    fi
else
    echo "[$(date '+%H:%M:%S')] WARNING: GGUF model not found at $MODEL_SRC_DIR/$MODEL_FILENAME; am flow will fail until installed."
fi

echo "[$(date '+%H:%M:%S')] Dependency setup complete."
