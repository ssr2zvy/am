# am Machine Commands

This document describes the bash functions provided by `amupa/machine/ammachine.sh` for managing the am development and runtime containers.

## Related Documentation

- `amdcc/amupa/n.md` - Development container workflow details
- `amc/amupa/n.md` - Runtime container workflow details

## Setup

### Windows Initial Setup

On a fresh Windows machine:

**1. Add amupa to PATH (one-time):**

Open PowerShell and run:
```powershell
[Environment]::SetEnvironmentVariable("Path", "$([Environment]::GetEnvironmentVariable('Path', 'User'));C:\path\to\am\amupa", "User")
```

Replace `C:\path\to\am\amupa` with the absolute path to your amupa directory (e.g. `C:\Users\vin\am\amupa`). Then restart the terminal.

**2. Run setup (requires Administrator):**
```cmd
am upa
```

This will:
- Check administrator privileges
- Enable WSL Windows features (VirtualMachinePlatform, Microsoft-Windows-Subsystem-Linux)
- Install WSL via `wsl --install --no-distribution`
- Install or update Podman to latest version via winget

If features need to be enabled, the script will prompt for reboot and exit. After rebooting, run `am upa` again as Administrator to continue.

Use `-n` for a dry run that only checks without making changes:
```cmd
am upa -n
```

**Options** (can be combined in any order):
- `-n` = dry run (check only, no changes)
- `--debug` = verbose debug output

```cmd
am -n              # Dry run: check if machine exists/running
am -pm -n          # Dry run: check if would create machine
am --debug         # Run with debug output
am -pm --debug -n  # Dry run create with debug
gn -n              # Dry run: check if would stop
gn -pm -n          # Dry run: check if would delete
```

### Windows Daily Usage

**First time setup** - create and start the podman machine:
```cmd
am -pm
```

This will:
1. Create the podman machine using `amupa/ammachine.taml` playbook
2. Start the machine
3. SSH into the machine with all commands available

**Daily use** - start existing machine and SSH:
```cmd
am
```

This will:
1. Start the machine if not running (fails if machine doesn't exist)
2. SSH into the machine with all commands available

**Stop the machine** - exit the SSH session and run:
```cmd
gn
```

**Delete the machine** (full reset):
```cmd
gn -pm
```

### Windows Update
To update WSL and/or Podman to specific versions while preserving container images (requires Administrator):
```cmd
am -u
```
This will:
1. Check for running containers (must stop first)
2. Read target WSL / Podman versions (and their URLs) from `amupa/versions.txt`; the script prompts you to edit the file before continuing so all pins live in one place
3. Validate versions exist (pinned `WSL_URL` first, else GitHub releases for WSL; winget for Podman, with `Podman_URL` as a fallback)
4. Save all container images to a backup tar
5. Update WSL via `.msixbundle` from the pinned URL
6. Update Podman via winget (handles downgrades by uninstalling first), falling back to the pinned URL
7. Recreate the podman machine with `--memory 8192 --cpus 4` and the playbook
8. Reload and verify all images
9. Clean up backup files
### VM and Container Resources
The Podman VM and the two project containers must be sized for the embedded LLM that `am flow` runs (Phi-4-mini-instruct Q4_K_M, ~2.5 GB on disk, ~3 GB peak working set at 4K ctx). The defaults (2 GB VM, no container cap) are too small.
- `amupa/upaupa/am-pm.ps1` and `amupa/upaupa/am-u.ps1` create the VM with `podman machine init --memory 8192 --cpus 4`.
- `amdcc/container-build/amcontainer/gcontainer.sh` and `amc/amupa/amcontainer/gcontainer.sh` start each container with `podman run --memory 6g`.
- The same values are documented (as notes only) in `amupa/versions.txt` under `AMMACHINE_MEMORY_MB` / `AMMACHINE_CPUS` / `AMCONTAINER_MEMORY`.

**Re-run support:** If a reboot is required (e.g. after WSL update), simply run `am -u` again. The script detects existing backup files and resumes from where it left off.

**Backup files** (in `amupa/` during update):
- `amu_backup.tar` - Saved container images
- `amu_backup_images.txt` - List of image names for verification
- `amu_backup_meta.txt` - Target versions for re-run

### Windows Uninstall

To completely remove Podman and WSL (requires Administrator):
```cmd
gn upa
```

This will prompt (u/N) for each step:
- Check for other podman machines (warns if found)
- Remove all podman machines
- Uninstall Podman via winget
- Clean up Podman data folders
- Unregister all WSL distros
- Uninstall WSL (`wsl --uninstall`)
- Disable WSL features (Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform)

If Windows features are disabled, a reboot is required. The script will prompt and exit.

Use `-n` for a dry run:
```cmd
gn upa -n
```

### Manual Setup (Linux or existing podman machine)

1. Open your bash configuration file:
   ```sh
   nano ~/.bashrc
   ```

2. Add this line at the end of the file:
   ```sh
   source /mnt/c/users/vin/am/amupa/machine/ammachine.sh
   ```

3. Save and reload:
   ```sh
   source ~/.bashrc
   ```

4. Verify by running:
   ```sh
   upaupa
   ```

**Exported variables:** After sourcing, these variables are available:
- `$am_loc` - Path to am root directory
- `$amdcc_loc` - Path to amdcc (development container)
- `$amc_loc` - Path to amc (runtime container)

## Directory Structure

```
am/
├── amupa/            # Machine-level scripts and docs (add to PATH)
│   ├── am.cmd        # Windows: init/start machine + SSH (also: am upa)
│   ├── ma.cmd        # Windows: stop podman machine (also: gn upa)
│   ├── n.md          # This documentation
│   ├── machine/      # Podman machine config
│   │   ├── ammachine.sh   # Bash functions (source this)
│   │   └── ammachine.taml # Ansible playbook for machine init
│   └── upaupa/       # PowerShell scripts
│       ├── amhelpers.ps1  # Shared helper functions
│       ├── am.ps1         # am (start machine + SSH)
│       ├── am-pm.ps1      # am -pm (create + start + SSH)
│       ├── am-upa.ps1     # am upa (setup WSL + Podman)
│       ├── am-u.ps1       # am -u (update WSL + Podman)
│       ├── gn.ps1         # gn (stop machine)
│       ├── gn-pm.ps1      # gn -pm (stop + delete machine)
│       └── gn-upa.ps1     # gn upa (uninstall)
├── amdcc/            # Development container project
│   ├── ammounted/    # Mounted into container
│   │   └── am/
│   │       ├── shv/  # Zig source tree
│   │       └── upa/  # Built binaries + data
│   ├── container-build/  # Container scripts (see amdcc/container-build/n.md)
│   └── vinvin/       # Backup location
│       └── am_/      # Timestamped backups
├── amc/              # Runtime container project
│   ├── amupa/        # Container scripts (see amc/amupa/n.md)
│   │   └── amcontainer/
│   │       └── am/upa/  # Baked binaries + data
│   └── vinvin/       # Backup location
│       └── am_/      # Timestamped backups
└── vinvin/           # Project-level backup location
    └── am_/          # Timestamped backups (upaupa vinvin am)
```

## Data File Locations

**Viewer HTML:**
- Source: `shv/src/upa/viewer.html`
- Embedded into `amconfig` at build time
- Written to `upa/viewer.html` when `amconfig` runs

**Database files:**
- Location: `upa/vin/*.db`
- Primary DB: `upa/vin/am.db`
- Created/managed by `am` at runtime

**Error log:**
- Location: `upa/vin/errors.log`
- Append-only log of error codes and messages
- Created by `am` when errors occur (DB write failures, etc.)

---

## Container Management

### amdcc (development container)

```sh
amdcc                      # Toggle container (begin/stop)
amdcc --debug              # Toggle with debug output
amdcc image                # Rebuild final image, restart
amdcc image --builder      # Rebuild builder + final, restart
amdcc image --base         # Rebuild base + builder + final, restart
```

### amc (runtime container)

```sh
amc                        # Toggle container (begin/stop)
amc --debug                # Toggle with debug output
amc image                  # Rebuild final image, restart
amc image --builder        # Rebuild builder + final, restart
amc image --base           # Rebuild base + builder + final, restart
```

---

## Build Commands

### amdccupa

Runs tests and release build in the amdcc container:

```sh
amdccupa                   # Run tests + release build
amdccupa --debug           # With debug output
amdccupa -m "message"      # With git commit message
amdccupa --debug -m "msg"  # Both options
```

If no `-m` message is provided, the git commit defaults to a timestamp.

**Note:** `amdccupa` stops services before building. Run `amupaupa am` afterward to restart.

---

## Service Control

### amupaupa (amdcc container)

Controls am services inside the amdcc development container:

```sh
amupaupa am                # Begin am TUI (ttyd) + viewer (httpd)
amupaupa gn                # Stop all services gracefully
amupaupa status            # Show status
amupaupa status --upa      # Show detailed process status
amupaupa vin               # Show URLs only
amupaupa --debug am        # Begin with debug output
```

**Session persistence:** Uses dtach so am survives browser tab close/refresh. Multiple tabs share the same session.

**am command outputs:**
- `upa: began` - Began fresh
- `upa: began from partial` - Recovered from partial state
- `upa: already began` - Already running
- `upa: exception` - Failed to begin

**gn command outputs:**
- `upa: stopped` - Stopped from live
- `upa: stopped from partial` - Cleaned up partial state
- `upa: already stopped` - Nothing was running

**Status outputs:**
- `upa: live` - All services running (am + dtach + ttyd + httpd)
- `upa: partial` - Some services running but not all
- `upa: not live` - Nothing running

**URLs (port 7682 for TUI, port 8080 for viewer):**
```
am ttydc: http://localhost:7682
viewer: http://localhost:8080
```

**Note:** amdcc uses port 7682 to avoid conflict with amc (which uses 7681).

### amupa (amc container)

Controls am services inside the amc runtime container:

```sh
amupa am                   # Begin am TUI (via ttyd)
amupa gn                   # Stop am gracefully
amupa status               # Show status
amupa status --upa         # Show detailed process status
amupa vin                  # Show URLs only
amupa --debug am           # Begin with debug output
```

**Session persistence:** Uses dtach so am survives browser tab close/refresh. Multiple tabs share the same session.

**Status outputs:**
- `upa: live` - All services running (am + dtach + ttyd)
- `upa: partial` - Some services running but not all
- `upa: not live` - Nothing running

### amcupa (amc sync)

Toggles background sync between host and amc container for the `vin/` directory:

```sh
amcupa                     # Toggle sync on/off
amcupa status              # Show sync status
amcupa begin               # Start sync
amcupa end                 # Stop sync
```

**Note:** Sync starts automatically when the amc container starts and stops when it stops. Use `amcupa` only if you need to manually control sync.

**How it works:** Uses `podman cp` to copy `vin/` between host and container every 3 seconds (configurable via `SYNC_INTERVAL` env var). No volume mount is used.

**Outputs:**
- `gu: sync began` - Sync started
- `gu: sync stopped` - Sync stopped
- `gu: sync already running` - Sync was already active
- `gu: sync not running` - Sync was already stopped
- `gu: container not running` - Cannot start sync without container

**Status outputs:**
- `gu: sync running (pid <N>)` - Sync is active
- `gu: sync not running` - Sync is stopped
- `gu: sync DISABLED (corruption recovery failed)` - Sync permanently disabled
- `gu: WARNING: corruption marker present` - Corruption detected but sync still running

**Corruption handling:**
If the am TUI writes a `.am_corrupt` marker file (on database corruption), sync automatically:
1. Stops syncing
2. Restores from latest vinvin backup
3. Monitors for 3 minutes (configurable via `RECOVERY_MONITOR_SECS`)
4. Resumes if stable, or disables permanently if corruption reappears

**Corruption outputs:**
- `gu: corruption detected, stopping sync` - Corruption marker found
- `gu: restore failed` - No vinvin backup available or restore failed
- `gu: restore synced to container` - Restore complete
- `gu: monitoring for <N> seconds...` - Recovery monitoring period
- `gu: recovery successful, resuming normal sync` - Monitoring passed
- `gu: corruption reappeared during monitoring` - Re-corrupted during monitoring
- `gu: disabling sync permanently (re-run service to re-enable)` - Sync disabled
- `gu: sync disabled due to previous corruption` - Attempt to start disabled sync
- `gu: remove <path> and restart to re-enable` - How to re-enable

---

## Backup Commands

### upaupa vinvin

Diff-based backup system with file watching. Backups are stored as compressed patches.

**Targets:** `amdcc`, `amc`, `amupa`

#### Toggle watchers

```sh
upaupa vinvin on                  # Enable all target watchers
upaupa vinvin off                 # Disable all target watchers
upaupa vinvin amdcc on            # Enable amdcc watcher only
upaupa vinvin amc off             # Disable amc watcher only
upaupa vinvin status              # Show status of all targets
```

**How watchers work:**
- Each enabled target has a background watcher that monitors for file changes
- When changes are detected, a 60-second cooldown starts
- If more changes occur during cooldown, the timer resets
- After 60 seconds of no changes, a backup is triggered
- Watchers start automatically via `ammachineupa` when WSL shell opens

#### Manual operations

```sh
upaupa vinvin backup amdcc        # Manual backup trigger
upaupa vinvin list amdcc          # List available restore points
upaupa vinvin restore amdcc       # Restore to latest
upaupa vinvin restore amdcc base  # Restore to initial snapshot
upaupa vinvin restore amdcc abc123  # Restore to specific hash
```

**Restore behavior:**
- Outputs to `<target>/vinvin/snapshots/<hash>/`
- Does not overwrite the source directory directly
- Use the output to manually copy files back if needed

#### Configuration

```sh
upaupa vinvin config amdcc              # Show all config
upaupa vinvin config amdcc enabled      # Show single value
upaupa vinvin config amdcc enabled on   # Set value
```

**Config options (stored in `<target>/vinvin/.upa`):**

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | off | Watcher on/off |
| `medium_threshold_mb` | 20 | Files above this size use versioned storage |
| `large_threshold_mb` | 1000 | Files above this use fewer versions |
| `medium_versions` | 3 | Versions to keep for medium files (20MB-1GB) |
| `large_versions` | 2 | Versions to keep for large files (>1GB) |
| `large_keep_hours` | 24 | Hours to keep old large file versions |
| `cooldown_seconds` | 60 | Seconds to wait after last change before backup |
| `exclude` | (empty) | Comma-separated paths to exclude |

**Large file handling:**
- Files 20MB-1GB: Keep 3 versions (newest)
- Files >1GB: Keep 2 versions, old version expires after 24 hours unless no new changes
- Container images (~2GB each) fall into the large tier

**Backup structure:**
```
<target>/vinvin/
  .upa                # Config file
  base/               # Initial full snapshot
  current/            # Latest state (convenience copy)
  patches/            # <hash>.patch.gz compressed diffs
  history.txt         # <hash> <timestamp> <summary>
  large_files/        # Versioned copies of large files
  snapshots/          # Restore output directory
```

---

## Shared Dependencies

### upaupa image

Syncs shared dependencies from `amupa/upaupaLocal/` to both container build contexts:

```sh
upaupa image            # Sync dependencies
upaupa image --debug    # Sync with verbose output
```

**What gets synced:**
- **To amdcc:** binaries (busybox, dtach, ttyd), build deps (sqlite, zig, dtach source), scripts
- **To amc:** binaries (busybox, dtach, ttyd), scripts (no build deps)

**Entrypoint handling:** Container-specific entrypoints are renamed during sync:
- `gentrypoint-amdcc.sh` → `gentrypoint.sh` (in amdcc)
- `gentrypoint-amc.sh` → `gentrypoint.sh` (in amc)

---

## Reset Commands

### amreset

Resets container state with granular control over what to remove:

```sh
amreset <amdcc|amc> --binaries   # Remove am and amconfig binaries
amreset <amdcc|amc> --viewer     # Remove viewer.html
amreset <amdcc|amc> --amd        # Backup + remove vin/ folder
amreset <amdcc|amc> --image      # Stop container + remove container/images (keeps base)
amreset <amdcc|amc> --all        # All of the above
amreset <amdcc|amc> --debug      # Show verbose output
```

**Options can be combined:**
```sh
amreset amdcc --binaries --viewer  # Remove binaries and viewer only
amreset amc --amd --image          # Backup/remove db and remove images
```

**What each option removes:**
- `--binaries`: `upa/am` and `upa/amconfig`
- `--viewer`: `upa/viewer.html`
- `--amd`: `upa/vin/` folder (backs up via vinvin first)
- `--image`: Stops container, removes container and builder/final images (keeps am-base)
- `--all`: All of the above

### amreset line ending conversion

Converts line endings in files:

```sh
amreset --oslf <file>     # Convert to LF (Unix)
amreset --oscrlf <file>   # Convert to CRLF (Windows)
```

**file_path** can be:
- Absolute path (e.g. `/mnt/c/path/to/file.sh`)
- Relative to `$am_loc` (e.g. `amdcc/amupa/somescript.sh`)

---

## Publish Commands

### upaupa publish

Publishes built binaries from amdcc to amc:

```sh
upaupa publish             # Copy amconfig
upaupa publish --build     # Build first, then copy
upaupa publish all         # Copy amconfig + db files
upaupa publish --debug     # With verbose output
upaupa publish --build all # Build, then copy amconfig + db
```

**Note:** `viewer.html` is embedded in `amconfig` and written when `amconfig` runs. It is not copied by publish.

**Outputs:**
- `building...` - Running build (with --build)
- `moving...` - Copying files
- `moved.` - Success

---

## Machine Reset

### ammachineupa

Applies changes from `machine/` to the WSL podman machine and starts vinvin watchers:

```sh
ammachineupa              # Copy updated scripts to WSL + start vinvin watchers
ammachinereset            # (alias for ammachineupa)
```

**Actions:**
1. Creates `~/.am/` directory structure in WSL
2. Copies `ammachine.sh` and all `gscripts/*.sh` to `~/.am/`
3. Fixes CRLF line endings to LF
4. Updates `~/.bashrc` to source from `~/.am/` instead of `/mnt/c/`
5. Reloads the shell
6. Starts vinvin watchers for any enabled targets

**Use case:** When you edit scripts in `amupa/machine/` and want changes to take effect without recreating the podman machine.

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `am upa` | Windows setup (WSL + Podman) |
| `am upa -n` | Windows setup dry run |
| `gn upa` | Windows uninstall (machines + Podman + WSL) |
| `gn upa -n` | Windows uninstall dry run |
| `am -pm` | Create + start podman machine + SSH |
| `am` | Start existing podman machine + SSH |
| `am -n` | Dry run: show what am would do |
| `am --debug` | Run with debug output |
| `gn -pm` | Stop + delete podman machine |
| `gn` | Stop podman machine |
| `gn -n` | Dry run: show what gn would do |
| `gn --debug` | Run with debug output |
| `am -u` | Update WSL + Podman (preserves images) |
| `am -u -n` | Update dry run: check versions |
| `amdcc` | Toggle dev container |
| `amdccupa` | Test + release build |
| `amdccupa -m "msg"` | Build with git message |
| `amc` | Toggle runtime container |
| `amcupa` | Toggle amc sync on/off |
| `amupaupa am` | Begin dev services |
| `amupaupa gn` | Stop dev services |
| `amupaupa status` | Dev status |
| `amupa am` | Begin runtime services |
| `amupa gn` | Stop runtime services |
| `amupa status` | Runtime status |
| `upaupa vinvin on` | Enable all vinvin watchers |
| `upaupa vinvin off` | Disable all vinvin watchers |
| `upaupa vinvin status` | Show vinvin watcher status |
| `upaupa vinvin backup <target>` | Manual backup trigger |
| `upaupa vinvin list <target>` | List restore points |
| `upaupa vinvin restore <target>` | Restore to latest |
| `upaupa vinvin config <target>` | View/set config |
| `upaupa image` | Sync shared deps to build contexts |
| `upaupa publish` | Publish amconfig to runtime |
| `upaupa publish --build` | Build then publish |
| `upaupa publish all` | Publish amconfig + db |
| `amreset <target> --all` | Full reset (binaries, viewer, db, images) |
| `amreset --oslf <file>` | Convert file to LF (Unix) |
| `amreset --oscrlf <file>` | Convert file to CRLF (Windows) |
| `ammachineupa` | Apply machine/ changes to WSL + start watchers |

