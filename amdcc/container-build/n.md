# am container workflow

This document explains how the two main workflow scripts interact:

- `gcontainer.sh` – container lifecycle (build/run/stop the amdcc container)
- `gu.sh` – running tests/builds/cleans inside the running container

---

## gcontainer.sh

Location: `container-build/amcontainer/gcontainer.sh`

### Purpose

- Build the `amdcc-image` container image from `container-build/amcontainer/Containerfile` (if it does not already exist).
- Start the `amdcc` container with the project mounted in.
- If the container is already running, stop it.

### Behavior

1. **Resolve paths**
   - Computes the project root based on the script location.
   - Sets:
     - `CONTAINER_DIR = <root>/container-build/amcontainer`
     - `MOUNT_SRC   = <root>/ammounted`
     - `MOUNT_DST   = /container_upa/container_mount`
     - `APP_DIR_NAME = am`

2. **Image mode (`image` argument)** 
   - Invoked as `sh container-build/amcontainer/gcontainer.sh image [--base|--builder] [--debug]`.
   - Always stops and removes any existing `amdcc` container before rebuilding.
   - Rebuild behavior:
     - `image --base`:
       - Rebuilds the base image `am-base` from `baseContainerfile`.
       - Rebuilds the builder image `amdcc-builder` (Containerfile target `builder`).
       - Rebuilds the final image `amdcc-image` (Containerfile default target).
     - `image --builder`:
       - Rebuilds `amdcc-builder` and then `amdcc-image` (reusing the existing base).
     - `image` (no extra flags):
       - Ensures `am-base` and `amdcc-builder` exist (builds them if missing).
       - Rebuilds only the final `amdcc-image`.
   - After the images are built, `gcontainer.sh` starts a fresh `amdcc` container.
   - If `--debug` is passed, `gcontainer.sh` prints full `podman` output and sets `DEBUG=1` in the container environment (entrypoint scripts will not `set -e` in this mode).

3. **Toggle mode (no arguments)**
   - If the container is running:
     - Prints: `Container running. Stopping...`
     - Runs: `podman stop amdcc` and removes the container.
   - If the container is not running:
     - Ensures the final image `amdcc-image` exists, building `am-base` and `amdcc-builder` first if needed using `baseContainerfile` and `Containerfile`.
     - Starts the container:
       - `podman run --pull=never -d [--rm] --name amdcc -p 7682:7681 -p 8080:8080 -v <root>/ammounted:/container_upa/container_mount amdcc-image`
         - Port 7682 on host maps to 7681 in container (ttyd for TUI)
         - Port 8080 on host maps to 8080 in container (httpd for viewer)
         - `--rm` is included by default so the container is removed automatically when it stops.
         - `--rm` is omitted in DEBUG mode so the container stays for log inspection.
         - The bind mount mirrors the host `ammounted/` tree at `/container_upa/container_mount`.
     - Verifies the container stays running for a few seconds; if it crashes, recent logs are printed.
5. **Entrypoint inside container**
   - The container's CMD is `/container_upa/gentrypoint.sh`.
   - On startup, `gentrypoint.sh`:
     - Runs `upa-code-dependencies.sh` to copy vendored sqlite source from `/container_upa/sqlite_files/` to mounted `am/shv/upaupa/sqlite/`
     - Prints usage instructions
     - Execs `sleep infinity` to keep container alive
   - Container stays idle until services are manually started via `vv.sh`
   - After first run, manually copy sqlite files from `ammounted/am/shv/upaupa/sqlite/` to `amupa/amcontainer/upaupaLocal/` on the host so future image builds use the local copy.

6. **vv.sh control commands**
   - From the host, you can control am and viewer services inside the container:
     ```sh
     podman exec amdcc /container_upa/vv.sh am           # Start all services (idempotent)
     podman exec amdcc /container_upa/vv.sh gn           # Stop all services gracefully
     podman exec amdcc /container_upa/vv.sh status       # Show state
     podman exec amdcc /container_upa/vv.sh status --upa # Show detailed process info
     podman exec amdcc /container_upa/vv.sh vin          # Show URLs
     podman exec amdcc /container_upa/vv.sh --debug am   # Start with debug output
     ```
  - For backups, use host-side command: `upaupa vinvin amdcc [options]` (see am/amupa/n.md)
   - **Session persistence:** dtach allows am to survive browser tab close/refresh. Multiple tabs share the same session.
   - `am` command outputs:
     - `upa: began` - started fresh from not live
     - `upa: began from partial` - recovered from partial state
     - `upa: already began` - already running
     - `upa: exception` - failed to start
   - `gn` stops am gracefully (WAL checkpoint), outputs:
     - `upa: stopped` - stopped from live
     - `upa: stopped from partial` - cleaned up partial state
     - `upa: already stopped` - nothing was running
   - `status` shows: `upa: live`, `upa: partial`, or `upa: not live`
     - `upa: live` - all services running (am + dtach + ttyd + httpd)
     - `upa: partial` - some services running but not all
     - `upa: not live` - nothing running
   - `status --upa` shows detailed per-process status
   - `vin` shows URLs only:
     ```
     am ttydc: http://localhost:7682
     viewer: http://localhost:8080
     ```
     Note: amdcc uses port 7682 to avoid conflicts with amc (which uses 7681).
   - `--debug` flag shows detailed output for troubleshooting

### Typical usage

From the project root (`amdcc/`):

```sh
sh container-build/amcontainer/gcontainer.sh                    # toggle container (start/stop)
sh container-build/amcontainer/gcontainer.sh --debug            # toggle with debug output
sh container-build/amcontainer/gcontainer.sh image              # rebuild final image and restart container (using cached base + builder)
sh container-build/amcontainer/gcontainer.sh image --base       # rebuild base + builder + final, then restart
sh container-build/amcontainer/gcontainer.sh image --builder    # rebuild builder + final, then restart
sh container-build/amcontainer/gcontainer.sh image --debug      # rebuild with debug output
```

- First run of `gcontainer.sh`: builds the necessary images and starts the container.
- Subsequent `gcontainer.sh` runs (no args): stop the running container (and because of `--rm`, it is removed).
- `gcontainer.sh image [flags]`: rebuild the requested stages (`--base`, `--builder`, or final only) and then start a fresh container.

### Podman host functions (Linux host or podman machine)

On the host that runs podman (either a Linux machine or a podman machine/WSL VM), add this line to your `~/.bashrc`:

```sh
source /mnt/c/users/vin/am/amupa/machine/ammachine.sh
```

See `am/amupa/n.md` for full documentation of all commands including:
- `amdcc`, `amdccupa` - Container and build management
- `amupaupa` - Service control commands
- `upaupa vinvin` - Backup commands

### Debug Mode

All scripts support `--debug` for troubleshooting:
- `gcontainer.sh --debug` - Show podman output and pass DEBUG=1 to container
- `gu.sh --debug [command]` - Show full build output including warnings
- `vv.sh --debug [command]` - Show amconfig/httpd/ttyd startup details

---

## gu.sh

Location: `container-build/gu.sh`

### Purpose

- Run Zig tests and builds **inside** the running `amdcc` container.
- Delegate actual work to project-local scripts under `am/amupa/n/`:
  - `gtest.sh` – tests
  - `gbuild.sh` – debug/release builds + auto-commit
  - `gclean.sh` – remove Zig cache and `zig-out/`

### Preconditions

- The `amdcc` container must be running (started via `gcontainer.sh`).
- `ammounted/` is mounted into the container at `/container_upa/container_mount`.

If the container is not running, `gu.sh` prints an error and tells you to run `gcontainer.sh` first.

### Paths used inside the container

- `APP_DIR_NAME = am`
- Script directory in the container:
  - `APP_SCRIPT_DIR = /container_upa/container_mount/am/amupa/n`
  - `BUILD_SCRIPT = $APP_SCRIPT_DIR/gbuild.sh`
  - `TEST_SCRIPT  = $APP_SCRIPT_DIR/gtest.sh`
  - `CLEAN_SCRIPT = $APP_SCRIPT_DIR/gclean.sh`
- Zig source tree in the container:
  - `SHV_PATH = /container_upa/container_mount/am/shv`

### Commands

**All commands support `--debug` flag and build commands support `-m` for commit messages:**
```sh
gu.sh --debug test           # Show all test output
gu.sh --debug compile        # Show full build output
gu.sh --debug build          # Show full build output
gu.sh -m "message" build     # Build with custom commit message
gu.sh --debug -m "msg" build # Debug + custom message
```

#### `gu.sh test`

- Logs: `Running tests...`
- Cleans stale Zig cache if `build.zig` is newer than `.zig-cache`.
- Runs inside container:

  ```sh
  sh /container_upa/container_mount/am/amupa/n/gtest.sh
  ```

- `gtest.sh`:
  - `cd` into `SHV_PATH`.
  - Optionally clears stale `.zig-cache` and `zig-out/`.
  - Runs `zig build test`.

#### `gu.sh compile` (debug build)

- Logs: `Compiling (debug)...`
- Runs inside container:

  ```sh
  sh /container_upa/container_mount/am/amupa/n/gbuild.sh debug
  ```

- `gbuild.sh debug`:
  - `cd` into `SHV_PATH`.
  - Optionally clears stale `.zig-cache` and `zig-out/`.
  - Runs `zig build` (debug build).
  - Copies `zig-out/bin/am` and `zig-out/bin/amconfig` to `am/upa/` (flat structure).
  - Ensures a git repo exists under `am/shv/src` and auto-commits changes (default message is timestamp, use `-m` for custom message).
  - Prints: `Build succeeded.`

#### `gu.sh build` (release build)

- Logs: `Building (release)...`
- Runs inside container:

  ```sh
  sh /container_upa/container_mount/am/amupa/n/gbuild.sh release
  ```

- `gbuild.sh release`:
  - Same flow as debug, but runs `zig build -Doptimize=ReleaseSafe`.
  - Copies the release `am` and `amconfig` binaries into `am/upa/`.
  - `build.zig` targets `x86_64-linux-musl` for all builds (debug and release), so the release binary is fully static.
  - SQLite code is compiled from `shv/upaupa/sqlite/src/sqlite3.c` and baked into the `am` binary.
  - The resulting `am` binary has no external dependencies (sqlite or glibc) and can run in any Linux container or machine.
  - Auto-commits via git in `am/shv/src` (default message is timestamp, use `-m` for custom message).
  - Prints: `Build succeeded.`

#### `gu.sh clean`

- Logs: `Cleaning build artifacts...`
- Runs inside container:

  ```sh
  sh /container_upa/container_mount/am/amupa/n/gclean.sh
  ```

- `gclean.sh`:
  - `cd` into `SHV_PATH`.
  - Removes `.zig-cache` and `zig-out/` to force a fresh build next time.

### Summary

- Use **`gcontainer.sh`** to manage the `amdcc` container lifecycle.
- Use **`gu.sh`** to run test/build/clean commands *inside* that container by delegating to the scripts in `am/amupa/n/`.
- Use **`vv.sh am`** and **`vv.sh gn`** to start/stop am inside the container.
- The TUI is always served by the container (`vv.sh` + `ttyd`) based on the current `am/upa/am` binary.

### Distribution Layout

After a successful build, the `upa/` folder contains:

```
upa/
├── am              # Main TUI binary
├── amconfig        # Installer binary (sets up CLI + desktop)
└── vin/            # Data directory
    ├── am.db       # SQLite database
    └── errors.log  # Error log (created when errors occur)
```

To install on a new machine, run `./amconfig` from within the `upa/` folder. This creates:
- `~/.local/bin/am` - wrapper script for CLI access
- `~/.local/share/applications/am.desktop` - Linux desktop launcher
- `~/.config/am/install.path` - tracks installation location

If the `upa/` folder is moved, run `./amconfig` again to repair paths.

---

## Dependencies

All dependencies are defined in two pipe-delimited manifest files in `amupa/upaupaLocal/`:
- **`upaupaDependencies.txt`** — build tools + container infrastructure (amdcc only)
- **`upaDependencies.txt`** — what the am binary links/uses (both amdcc and amc)

Format: `name|path|url|version|type|format|download_format`

The Containerfile loops over these files to bring in each dependency (local file → curl fallback → hard fail) and place it into the container filesystem based on the `type` column.

### Upaupa Dependencies

| Name | Version | Type | What it does |
|------|---------|------|--------------|
| Zig | 0.14.1 | directory | Compiler. Statically links am against musl. Lives at `/usr/local/zig/` |
| busybox | 1.37.0-10.1 | core | Shell + core utilities for the scratch container. Lives at `/bin/` with symlinks (sh, cat, cp, httpd, etc.) |
| ttyd | 1.7.7 | program | Terminal web server. Exposes am TUI on port 7681. Lives at `/usr/local/bin/` |
| dtach | 0.9 | program | Session persistence. Allows am to survive browser tab close. Lives at `/usr/local/bin/` |
| git | (from apt) | — | Version control for auto-commits inside dev container. Not in the manifest — installed via apt |
| vv.sh | — | script | Service control (start/stop ttyd, httpd, dtach). Lives at `/container_upa/gscripts/` |
| run-am.sh | — | script | 3-line wrapper that dtach executes: `cd ~; am`. Lives at `/container_upa/gscripts/` |
| upa-code-dependencies.sh | — | script | Copies vendored sources from image into bind mount on first start |
| gentrypoint-amdcc.sh | — | script | Container entrypoint. Runs upa-code-deps, amconfig, starts httpd |
| gentrypoint-amc.sh | — | script | Runtime container entrypoint (amc only) |

### Upa Dependencies

| Name | Version | What it does |
|------|---------|------|
| SQLite | 3.53.3 | Vendored amalgamation (sqlite3.c/h). Statically linked into am. CVE-2026-11822/11824 patched |
| llama.cpp | b8146 | LLM inference engine. Statically linked into am. 7 CVEs patched. GPU backends stripped (CPU-only) |
| Model (GGUF) | Phi-4-mini-instruct Q4_K_M | 2.5 GB model file. Shipped as sibling to am binary. MIT licence |

The am binary is fully static (x86_64-linux-musl). At runtime it has zero dependencies on shared libraries. The only runtime file dependency is `am-model.gguf` which must be next to the `am` binary.

### Dependency Flow

```
amupa/upaupaLocal/          (shared source of truth — all vendored files live here)
    ↓  upaupa image
amdcc/amupa/amcontainer/upaupaLocal/   (build context copy)
    ↓  COPY in Containerfile
/tmp/local/                 (inside container during build)
    ↓  Containerfile loop (local → curl → fail)
/rootfs/                    (placed by type: /bin/, /usr/local/bin/, /gscripts/, /upa/)
    ↓  upa-code-dependencies.sh (at container start)
ammounted/am/shv/upaupa/   (bind-mounted source tree where build.zig finds them)
```

---

## Container Process

### Image Structure

Three images, built incrementally:

1. **am-base** (`baseContainerfile`): Ubuntu 24.04 + `apt-get upgrade`. Rebuild only for OS security patches.
2. **amdcc-builder** (Containerfile `builder` target): Installs apt tools (xz-utils, unzip, git), processes all dependencies from the manifest files, assembles `/rootfs/`.
3. **amdcc-image** (Containerfile default target): `FROM scratch`, copies `/rootfs/` from builder. Minimal final image.

### What the Builder Does

1. `COPY upaupaLocal/ /tmp/local/` — brings in all vendored files + manifest
2. Conditional apt install — only installs curl/ca-certificates if any dep is missing locally
3. Loops `upaupaDependencies.txt` + `upaDependencies.txt` — for each entry: local file → curl fallback → hard fail
4. App dep post-processing — SQLite: unzip + extract .c/.h files. llama.cpp: tar extract + strip GPU backends
5. Builds `/rootfs/` — loops by `type` column to place each dep in its destination
6. Copies glibc runtime libs (needed by ttyd, git) and git binary into `/rootfs/`

### Container Filesystem (`/rootfs/`)

```
/bin/busybox                          (+ symlinks: sh, cat, cp, ls, httpd, etc.)
/lib/x86_64-linux-gnu/                (glibc runtime for ttyd, git)
/lib64/ld-linux-x86-64.so.2
/usr/local/zig/                       (Zig compiler toolchain)
/usr/local/bin/zig                    (symlink → /usr/local/zig/zig)
/usr/local/bin/ttyd
/usr/local/bin/dtach
/usr/bin/git
/usr/lib/git-core/
/usr/share/git-core/
/container_upa/
├── gscripts/
│   ├── gentrypoint.sh                (container CMD)
│   ├── vv.sh                         (service control)
│   ├── upa-code-dependencies.sh      (first-start dep sync)
│   └── run-am.sh                     (dtach payload)
├── upa/
│   ├── sqlite_files/                 (sqlite3.c, .h, ext.h)
│   ├── llama_files/                  (include/, src/, ggml/)
│   └── model_files/                  (am-model.gguf)
└── container_mount/                  (bind mount point → ammounted/)
```

### Startup Flow

1. Container starts → `gentrypoint.sh` runs
2. `upa-code-dependencies.sh` copies vendored sources from `/container_upa/upa/` into the bind-mounted source tree at `/container_upa/container_mount/am/shv/upaupa/` (idempotent — skips if already present)
3. `amconfig` runs to generate `viewer.html`
4. `busybox httpd` starts as PID 1 serving viewer on port 8080
5. Container idles until `vv.sh am` is called to start the TUI

### Debug Mode

All scripts support `--debug` for troubleshooting:
- `gcontainer.sh --debug` — show podman output, pass DEBUG=1 to container
- `gu.sh --debug [command]` — show full build output including warnings
- `vv.sh --debug [command]` — show amconfig/httpd/ttyd startup details
- In DEBUG mode, `gentrypoint.sh` runs `sleep infinity` instead of httpd, so you can exec in and debug manually
