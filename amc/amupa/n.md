# am Server Container Workflow

This document explains the end-to-end flow from container setup to running am.

## Overview

The container serves two endpoints:
- **Port 7681**: am TUI via ttyd (terminal in browser)
- **Port 8080**: viewer.html (static file server)

## Architecture

**Baked into image** (at build time):
- `am` - TUI binary
- `amconfig` - installer (creates viewer.html when run)

**Created at container startup** (by amconfig):
- `viewer.html` - static viewer

**Synced** (via podman cp):
- `vin/` - db files and errors.log sync between container and host
- Sync starts automatically when container starts
- Use `amcupa` to toggle sync on/off manually

## File Structure

```
amc/
├── amupa/
│   ├── n.md
│   ├── gu.sh                   # Sync script (podman cp, no mount)
│   ├── amcontainer/
│   │   ├── Containerfile       # Container definition (amc-builder + amc-image)
│   │   ├── baseContainerfile   # Base image definition
│   │   ├── gcontainer.sh       # Container management script (build/toggle)
│   │   ├── am/                 # Build context (copied into image)
│   │   │   └── upa/
│   │   │       ├── am          # TUI binary
│   │   │       └── amconfig    # Creates viewer.html when run
│   │   └── upaupaLocal/
│   │       ├── gentrypoint.sh  # Container entrypoint
│   │       ├── vv.sh           # Service control script
│   │       ├── dtach-0.9.tar.gz # dtach source (built during image build)
│   │       ├── ttyd            # Optional cached ttyd binary
│   │       └── busybox         # Optional cached busybox binary
│   └── upagupa/
│       ├── code.txt            # Code dependencies documentation
│       └── container.txt       # Container dependencies documentation
└── vinvin/                     # Backup location
    └── am_/                    # Timestamped backups
```

## Container Paths

Inside the container at `/container_upa/container_mount/am/upa/`:
- `am` - TUI binary (baked in from build context)
- `amconfig` - installer (baked in from build context)
- `viewer.html` - created by amconfig at container startup
- `vin/` - synced with host via podman cp (not mounted)

## gcontainer.sh

Location: `amupa/amcontainer/gcontainer.sh`

### Usage

```sh
# Toggle container (start if stopped, stop if running)
sh amupa/amcontainer/gcontainer.sh
sh amupa/amcontainer/gcontainer.sh --debug            # Toggle with debug output

# Force rebuild runtime image (using cached base + builder) and start
sh amupa/amcontainer/gcontainer.sh image
sh amupa/amcontainer/gcontainer.sh image --debug      # Rebuild with debug output

# Rebuild all stages (base + builder + final) and start
sh amupa/amcontainer/gcontainer.sh image --base

# Rebuild builder + final (reuse base) and start
sh amupa/amcontainer/gcontainer.sh image --builder
```

### Behavior

**Default (toggle) mode:**
- If container running → stops sync, stops container
- If container stopped → starts container, starts sync (builds image if needed)

**Image mode (`image` argument):**
- Stops sync if running
- Removes existing container
- Rebuilds image from Containerfile
- Starts container with new image
- Starts sync

## gu.sh (Sync Script)

Location: `amupa/gu.sh`

Syncs `vin/` directory between host and container using `podman cp` instead of volume mounts.

### Usage

```sh
# Toggle sync on/off (or use amcupa alias)
sh amupa/gu.sh
sh amupa/gu.sh toggle

# Check sync status
sh amupa/gu.sh status

# Explicitly begin/end
sh amupa/gu.sh begin
sh amupa/gu.sh end
```

### Behavior

- **begin**: Copies host `vin/` into container, then begins background loop copying container→host every 3 seconds
- **end**: Does final sync out, stops background loop
- Sync auto-starts when container starts via `gcontainer.sh`
- Sync auto-stops when container stops
- PID file stored at `amupa/.gu_sync.pid`

### Environment Variables

- `SYNC_INTERVAL`: Seconds between syncs (default: 3)
- `BACKUP_EVERY`: Number of syncs between automatic vinvin backups (default: 10)
- `RECOVERY_MONITOR_SECS`: Seconds to monitor after corruption recovery (default: 180)
- `CONSOLIDATE_AGE_HOURS`: Hours before backups are consolidated (default: 48)
- `CONSOLIDATE_WINDOW_MINS`: Backup retention window in minutes (default: 8)

### Automatic Backups

Every 10 syncs (30 seconds by default), `gu.sh` automatically creates a timestamped backup of the database files to `vinvin/am_/`. This provides crash recovery without manual intervention.

### Backup Consolidation

To prevent disk exhaustion, backups older than 48 hours are automatically consolidated to one backup per 8-minute window. This runs during each backup cycle.

### Corruption Detection and Recovery

The sync system detects database corruption via the `.am_corrupt` marker file:

1. **Detection**: The Zig am binary detects SQLite corruption (SQLITE_CORRUPT, SQLITE_NOTADB) and writes `vin/.am_corrupt`
2. **TUI Display**: am shows "db corrupt - sync restoring" in the header and waits for recovery
3. **Sync Response**: gu.sh detects the marker, stops normal sync, and attempts recovery
4. **Recovery**:
   - Restore from the latest vinvin backup
   - Remove the `.am_corrupt` marker
   - Sync restored files to container
5. **Monitoring**: After restore, sync monitors for 3 minutes
   - If corruption reappears → sync disables permanently
   - If stable → normal sync resumes
6. **Permanent Disable**: If recovery fails or corruption recurs, sync creates `.gu_sync_disabled`
   - Remove this file and restart the container to re-enable sync

**Status with corruption:**
- `gu: sync DISABLED (corruption recovery failed)` - requires manual re-enable
- `gu: WARNING: corruption marker present` - corruption detected, recovery in progress

## gentrypoint.sh + vv.sh (Container Entrypoint and Control)

These scripts run inside the container.

### Container Startup

1. Container starts and executes `gentrypoint.sh`
2. `gentrypoint.sh`:
   - Enables `set -e` (unless DEBUG=1)
   - Runs `amconfig` which creates `viewer.html`
   - Copies viewer.html to isolated `/tmp/am_viewer/index.html`
   - Starts httpd as main process (PID 1) serving the viewer on port 8080
3. Viewer is immediately available at http://localhost:8080
4. am app is started separately via `vv.sh am`

### Service Control Commands

From the host, you can control the am app:
```sh
podman exec amc /container_upa/vv.sh am           # Start am (idempotent)
podman exec amc /container_upa/vv.sh gn           # Stop am gracefully
podman exec amc /container_upa/vv.sh status       # Show state
podman exec amc /container_upa/vv.sh status --upa # Show detailed process info
podman exec amc /container_upa/vv.sh vin          # Show URLs
podman exec amc /container_upa/vv.sh --debug am   # Start with debug output
```

For backups, use host-side command: `upaupa vinvin amc [options]` (see am/amupa/n.md)

**Session persistence:** dtach allows am to survive browser tab close/refresh. Multiple tabs share the same session.

**Command outputs:**
- `am` command:
  - `upa: began` - started fresh from not live
  - `upa: began from partial` - recovered from partial state
  - `upa: already began` - already running
  - `upa: exception` - failed to start
- `gn` command (stops am gracefully, WAL checkpoint):
  - `upa: stopped` - stopped from live
  - `upa: stopped from partial` - cleaned up partial state
  - `upa: already stopped` - nothing was running
- `status`: `upa: live`, `upa: partial`, or `upa: not live`
  - `upa: live` - all services running (am + dtach + ttyd)
  - `upa: partial` - some services running but not all
  - `upa: not live` - nothing running
- `status --upa`: detailed per-process status
- `vin`: Shows URLs only
- `--debug` flag shows detailed output for troubleshooting

### Flow

```
Container starts
    │
    └─→ gentrypoint.sh
           ├─→ Run amconfig (creates viewer.html)
           ├─→ Copy viewer.html to /tmp/am_viewer/index.html
           └─→ exec httpd (PID 1, port 8080) - viewer always available

[Manual: podman exec amc /container_upa/vv.sh am]
    ├─→ Start am in dtach session (persistent)
    └─→ Start ttyd (port 7681) attaching to dtach session
```

## Podman Host Functions

On the host that runs podman (either a Linux machine or a podman machine/WSL VM), add this line to your `~/.bashrc`:

```sh
source /mnt/c/users/vin/desktop/am/amupa/ammachine.sh
```

See `am/amupa/n.md` for full documentation of all commands including:
- `amc` - Container management
- `amcupa` - Sync toggle (start/stop background sync)
- `amupa` - Service control commands
- `upaupa vinvin` - Backup commands

### Debug Mode

All scripts support `--debug` for troubleshooting:
- `gcontainer.sh --debug` - Show podman output and pass DEBUG=1 to container
- `vv.sh --debug [command]` - Show amconfig/httpd/ttyd startup details

## Access Points

After running `gcontainer.sh` (or `amc` alias):

- **Viewer**: http://localhost:8080 (available immediately)
- **am TUI**: http://localhost:7681 (after `amupa am`)

## Dependencies

The **container** is minimal and owns all web-serving concerns:
- **Base**: Ubuntu 24.04
- **ttyd**: Terminal web server (local binary in upaupaLocal/) that exposes the existing `am` TUI over HTTP on port 7681
- **busybox**: Provides `httpd` for serving `viewer.html` on port 8080
- **dtach**: Session persistence (built from upaupaLocal/dtach-0.9.tar.gz) that allows am to survive browser tab close/reconnect

The Zig `am` binary itself is completely agnostic to ttyd/httpd/dtach; it just runs on a TTY. The container is what wires that TTY into a browser.

No development tools (no zig, no git, no build dependencies). Just runs the prebuilt am binary.

## ttyd Dependency

ttyd can be cached locally in `upaupaLocal/ttyd`. If not present, the Containerfile downloads it during build.

To cache locally (optional, faster rebuilds):
```sh
curl -fsSL https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o amupa/amcontainer/upaupaLocal/ttyd
```

## dtach Dependency

dtach source tarball must be present in `upaupaLocal/dtach-0.9.tar.gz`. It is built statically during container build.

To download (one-time):
```sh
curl -fsSL https://github.com/crigler/dtach/archive/refs/tags/v0.9.tar.gz -o amupa/amcontainer/upaupaLocal/dtach-0.9.tar.gz
```
