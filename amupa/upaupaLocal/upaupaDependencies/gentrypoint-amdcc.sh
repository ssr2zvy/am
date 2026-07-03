#!/bin/sh
# gentrypoint-amdcc.sh - Container entrypoint for amdcc (development)
# Runs dependency setup, then starts httpd (normal) or sleep infinity (debug)
#
# DEBUG=1: verbose output + sleep infinity (for manual debugging)
# Normal:  quiet setup + httpd as PID 1

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_SH="$SCRIPT_DIR/paths.sh"
am_path() {
    sh "$PATHS_SH" "$1"
}
UPA_DIR="$(am_path container.am.bin.dir)"
AMCONFIG_BIN="$(am_path container.am.amconfig)"
VIEWER_SERVE_DIR="$(am_path container.viewer.dir)"
HTTPD_PID_FILE="$(am_path container.pid.httpd)"
GSCRIPTS_DIR="$(am_path container.gscripts)"
UPA_CODE_DEPS_SH="$GSCRIPTS_DIR/upa-code-dependencies.sh"
PORT_VIEWER=${PORT_VIEWER:-8080}

# Exit on error unless debug mode
if [ "$DEBUG" != "1" ]; then
    set -e
fi

# Run dependency setup (amdcc-specific: copies sqlite files to mounted path)
if [ "$DEBUG" = "1" ]; then
    echo "Running dependency setup (verbose)..."
    sh "$UPA_CODE_DEPS_SH"
else
    sh "$UPA_CODE_DEPS_SH" >/dev/null 2>&1
fi

# Run amconfig to create viewer.html
if [ -x "$AMCONFIG_BIN" ]; then
    cd "$UPA_DIR"
    if [ "$DEBUG" = "1" ]; then
        echo "Running amconfig..."
        ./amconfig
    else
        ./amconfig >/dev/null 2>&1
    fi
fi

# Create viewer directory and copy viewer.html or create placeholder
mkdir -p "$VIEWER_SERVE_DIR"
if [ -f "$UPA_DIR/viewer.html" ]; then
    cp "$UPA_DIR/viewer.html" "$VIEWER_SERVE_DIR/index.html"
else
    # Create placeholder until amupaupa am generates real viewer
    cat > "$VIEWER_SERVE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>am viewer</title>
    <style>
        body { 
            display: flex; 
            align-items: center; 
            justify-content: center; 
            height: 100vh; 
            margin: 0; 
            font-family: monospace; 
            background: #1e1e1e; 
            color: #d4d4d4; 
        }
    </style>
</head>
<body>
    <div>am viewer not initialized - run amupaupa am</div>
</body>
</html>
EOF
fi

# Debug mode: sleep infinity for manual debugging
if [ "$DEBUG" = "1" ]; then
    echo "Container ready (debug mode)."
    echo "  Viewer dir: $VIEWER_SERVE_DIR"
    echo "  Use 'vv.sh am' to begin services, or debug manually."
    exec sleep infinity
fi

# Normal mode: httpd as PID 1
# Write pid file so vv.sh can detect httpd is running
echo $$ > "$HTTPD_PID_FILE"
echo "Container ready."
exec busybox httpd -f -p $PORT_VIEWER -h "$VIEWER_SERVE_DIR"
