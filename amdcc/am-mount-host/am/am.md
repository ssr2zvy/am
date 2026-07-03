# am

Entry capture for projects. `am` is a TUI plus a CLI that organises short
titled entries under named projects, with per-project title-prefix rules to
keep titles consistent.

## Setup

On initial launch or after moving / renaming the active binary folder
(`build-output/` when present, otherwise `upa/`):

1. `cd` into `build-output/` (or `upa/` if `build-output/` is absent)
2. Run `./amconfig`

This installs the `am` CLI command and a desktop entry. Re-run `./amconfig`
any time you move that folder.

After install, `am` is available from any shell. The wrapper script at
`~/.local/bin/am` also intercepts `am status` and `am uninstall` and routes
them to `amconfig`, so you have a single entry point.

## Projects

The default project name is `upa`. Running bare `am` opens the TUI on the
`upa` project, creating it automatically on first launch.

For additional projects, create them explicitly:

```sh
am project notes                # create a new project
am notes                        # open the TUI on it
```

You can have any number of projects. Each project owns its own entries and
its own title-prefix rules.

### Project management

```sh
am project <name>               # create a new project (seeds default prefixes)
am projects                     # list active projects
am project delete <name>        # soft-delete (cascades to entries)
```

Project names must match `[a-z0-9_-]+`, 1..64 chars. The following names are
reserved (they collide with CLI verbs) and rejected at create time:
`project`, `projects`, `view`, `list`, `delete`, `append`, `rewrite`,
`combine`, `prefix`, `status`, `uninstall`, `help`, `search`, `inspect`,
`upaupa`, `flow`.

## Title prefix rule

Every entry's title must begin with one of the project's allowed prefixes.
Titles that don't match are rejected at create / rephrase time.

Default prefix set (seeded into every new project):

```
explain          how is           decision:
explaining       why is           change:
describe         how to           fix:
describing       what is          investigate:
```

Each project owns its own copy, so projects can diverge: one project can drop
defaults and add domain-specific phrases without affecting another.

### Prefix management

```sh
am <project> prefix list                # show current allowed prefixes
am <project> prefix add "<phrase>"      # add a prefix to this project
am <project> prefix remove "<phrase>"   # remove a prefix from this project
am <project> prefix reset               # wipe and re-seed defaults
```

Phrases are trimmed and matched case-insensitively against the start of the
title (after leading whitespace). 1..64 characters after trimming.

## Entries

### Interactive (TUI)

```sh
am <project>
```

Opens the staging prompt scoped to `<project>`. Up/down arrows browse only
that project's history. Submit a new title to land in the detailed editor.

Controls:

- **Ctrl+G** — exit current view (editor → stage → app).
- **type `/g` + Enter** — show the help menu (works in both screens).
- **type `/gg` + Enter while browsing history** — soft-delete the current
  gentry (asks `u/N` to confirm).
- **type `::`** while editing — open command mode (`Ctrl+G` or `Esc`
  cancels; `Enter` executes).

If you submit a title that doesn't match an allowed prefix, the entry is
rejected and the staging screen redraws with a hint pointing at
`am <project> prefix list`.

### Non-interactive (CLI)

```sh
am <project> -t "<title>" -c "<content>"
am <project> -t "<title>" -c @path/to/body.gtext
am <project> -t "<title>" -c -
am <project> -t "<title>" -c "<part-1>" -c @part-2.gtext
```

Creates an entry without opening the TUI. Both `-t` and `-c` are required.
You can repeat `-c` to combine chunks in flag order (joined with a newline),
which is useful for agent flows that produce content in parts. Each `-c`
chunk can be literal text, `@file`, or `-` (stdin). The combined content
must parse as non-empty valid gtext; read/parse/validation failures abort
create with a specific error message. The title is prefix-validated the same
way as in the TUI. On success the new gid (`g00000001`-style) is printed.

### Appending to an existing entry

```sh
am <project> append <gid> -c "<content>"
am <project> append <gid> -c @path/to/body.gtext
am <project> append <gid> -c -
am <project> append <gid> -c "<part-1>" -c @part-2.gtext
```

Non-destructive: keeps the existing body and appends the combined `-c`
chunks to the end (joined to the existing content with a single newline so
top-level nodes stay as siblings). `<gid>` must exist, be active (not
soft-deleted), and belong to `<project>`; otherwise the command exits with
not-found. `-c` follows the same rules as create (required, repeatable,
combined in flag order with a newline between chunks). The resulting
combined body is re-validated as gtext before save. On success the gid is
printed as `appended: <gid>`.

### Rewriting an existing entry

```sh
am <project> rewrite <gid> -c "<content>"
am <project> rewrite <gid> -c @path/to/body.gtext
am <project> rewrite <gid> -c -
am <project> rewrite <gid> -c "<part-1>" -c @part-2.gtext
```

Destructive in-place overwrite of the entry's gtext body. The previous body
is replaced wholesale by the combined `-c` chunks once they pass gtext
validation; if validation fails, the previous body is left intact. The
title is not changed. `<gid>` must exist, be active (not soft-deleted), and
belong to `<project>`; otherwise the command exits with not-found. `-c`
follows the same rules as create (required, repeatable, combined in flag
order with a newline between chunks). On success the gid is printed as
`rewrote: <gid>`.

### Combining entries (and renaming)

```sh
am <project> combine <gid> -t "<new-title>"                     # rename
am <project> combine <gid-a> <gid-b> [<gid> ...] -t "<new-title>"
```

Merges the top-level nodes of one or more source entries into a single new
entry with `<new-title>`. Each source's body is trimmed of trailing
whitespace and joined with a single newline so the sources' top-level
nodes become siblings in the new entry's tree. The combined body is
gtext-validated before any write. `<new-title>` is prefix-validated like
create. After the new entry is written, each source entry is soft-deleted.
With a single `<gid>` this acts as a rename (new entry takes the source's
body under the new title; source is soft-deleted). On success the new gid
is printed as `combined: <new-gid>`.

### Listing, viewing, searching

```sh
am list <project>                       # newest first, one entry per line
am view <project> <gid>                 # title + body (separator: ---)
am <project> "<keyword>"                # case-insensitive substring search
                                        # over titles in <project>
am delete <project> <gid>               # soft-delete an entry
```

### Inspect (read-only database queries)

```sh
am inspect projects             # list projects with id and timestamps
am inspect prefix <project>     # list prefixes for a project
am inspect project <project>    # list all entries in a project
am inspect entry <gid>          # show entry details + associated session IDs
am inspect event <session_id>   # list events logged in a session
am inspect trace <session_id>   # list screen + key trace records in a session
am inspect snapshot <session_id>  # list cell-grid snapshots in a session
```

### Configuration

`am upaupa` manages persistent config values stored in the database.

```sh
am upaupa                       # show all config values
am upaupa <key>                 # show a single value
am upaupa <key> on|off          # set a value
```

Config keys:

- `log_event` — event logging (semantic events to events table, default: on)
- `log_trace` — trace logging (raw ANSI + key bytes, default: on)
- `log_snapshot` — snapshot logging (cell-grid snapshots, default: on)

Changes take effect on the next TUI launch.

## Flow (embedded LLM)

`am flow` sends a prompt to the embedded llama.cpp runtime and prints the
raw model reply. There is no intent classification, entry creation, or chat
templating in this version — the command is a thin pipe from your prompt to
the model's response.

```sh
am flow -c "<prompt>"
am flow -c @path/to/prompt.txt
am flow -c -
am flow -c "<part-1>" -c @part-2.txt
```

The `-c` flag follows the same rules as create / append / rewrite: at least
one is required, multiple are combined in flag order (joined with a newline),
and each value can be literal text, `@file`, or `-` (stdin).

The GGUF model file is staged as a sibling of the `am` binary by the
container dependency setup (`upa-code-dependencies.sh`). If the file is
missing, `am flow` exits with a data error.

## Development container notes (amdcc)

These notes describe the build/test helper scripts and vendored dependency
staging used by the `amdcc` container workflow.

### Build/test helper scripts

The helper scripts are sourced from:

- `amupa/upaupaLocal/upaupaDependencies/gbuild.sh`
- `amupa/upaupaLocal/upaupaDependencies/gtest.sh`
- `amupa/upaupaLocal/upaupaDependencies/gclean.sh`

At image build time they are installed into the container at:

- `/container_upa/gscripts/gbuild.sh`
- `/container_upa/gscripts/gtest.sh`
- `/container_upa/gscripts/gclean.sh`

`container-build-tool.sh` (in `amupa/upaupaLocal/environmentDependencies/`) invokes these container paths (not `am/amupa/n/*`).

Behavior summary:

- `gbuild.sh [--debug] [-m "<message>"] [debug|release]`
  - runs in `/container_upa/container_mount/am/shv`
  - clears `.zig-cache` + `zig-out` when `build.zig` is newer than cache
  - builds `am` + `amconfig`, then copies them to:
    - `/container_upa/container_mount/am/build-output/am`
    - `/container_upa/container_mount/am/build-output/amconfig`
  - attempts an auto-commit in `shv/src` if a git repo is present/initializable
- `gtest.sh [--debug]`
  - same stale-cache cleanup behavior
  - runs `zig build test` (filters harmless ABI fallback warning unless `--debug`)
- `gclean.sh [--debug]`
  - removes `/container_upa/container_mount/am/shv/.zig-cache` and `zig-out`

### Vendored dependency staging

At container startup, `gentrypoint.sh` runs
`/container_upa/gscripts/upa-code-dependencies.sh`, which stages vendored app
dependencies from image storage into the bind-mounted project tree.

Runtime helper scripts (`vv.sh`, `gentrypoint*.sh`) resolve the active binary
directory via `container.am.bin.dir`, which prefers `am/build-output/` and
falls back to `am/upa/` when `build-output/` is absent.

Current staged paths:

- SQLite:
  - source in image: `/container_upa/upa/sqlite_files/`
  - destination on mount: `am/shv/upaupa/sqlite/src/` (+ zip at `am/shv/upaupa/sqlite/`)
- llama.cpp:
  - source in image: `/container_upa/upa/llama_files/{include,src,ggml}`
  - destination on mount: `am/shv/upaupa/llama/{include,src,ggml}`
- GGUF model:
  - source in image: `/container_upa/upa/model_files/am-model.gguf`
  - destination on mount: `am/upa/am-model.gguf`

Copy behavior is idempotent and existence-gated:

- SQLite copies when `am/shv/upaupa/sqlite/src/sqlite3.c` is missing
- llama.cpp copies when `am/shv/upaupa/llama/include/llama.h` is missing
- model copies when `am/upa/am-model.gguf` is missing

`build.zig` compiles SQLite and llama.cpp from these staged mount paths and
targets `x86_64-linux-musl` (static linking flow).

## Structured Text Format (Detailed Editor)

Detailed text uses a structured format:

**Upa** — a topic or heading, ends with `:`

```
my topic:
```

**Sentence** — wrapped in `[]`

```
[This is a sentence or note.]
```

**Connection** — wrapped in `||`, can contain nested upas

```
|This links to another topic|
```

Example structure:

```
project ideas:
        [Main goal is to build something useful.]
        |related reading|
                books to check:
                        [The Pragmatic Programmer]
```

Indentation is one tab character (displayed as 8 spaces). Use `::` commands
in detailed text to navigate and manipulate the structure (see `/g` help).

## CLI reference summary

```
am                                      Open TUI on default project (upa)
am <project>                            Open TUI on <project>
am <project> -t "<t>" -c "<c>" [-c ...] Non-interactive create (-c required)
am <project> "<keyword>"                Search
am flow -c "<prompt>" [-c ...]          Query embedded LLM, print raw reply

am project <name>                       Create project
am project delete <name>                Soft-delete project (cascades)
am projects                             List active projects

am list <project>                       List entries
am view <project> <gid>                 Show one entry
am <project> append <gid> -c "<c>" [-c ...]
                                        Append chunks to entry body (-c required)
am <project> rewrite <gid> -c "<c>" [-c ...]
                                        Overwrite entry body (-c required)
am <project> combine <gid> [<gid> ...] -t "<title>"
                                        Merge entries into new one (rename if 1 src);
                                        sources soft-deleted
am delete <project> <gid>               Soft-delete entry

am <project> prefix list                List allowed prefixes
am <project> prefix add "<phrase>"      Add a prefix
am <project> prefix remove "<phrase>"   Remove a prefix
am <project> prefix reset               Restore defaults

am inspect projects                     List projects (with ids)
am inspect prefix <project>             List prefixes
am inspect project <project>            List entries
am inspect entry <gid>                  Show entry + session IDs
am inspect event <session_id>           List events in session
am inspect trace <session_id>           List trace records in session
am inspect snapshot <session_id>        List snapshots in session

am upaupa                               Show all config values
am upaupa <key> on|off                  Set a config value

am status                               Install status (via amconfig)
am uninstall [--amd] [-n] [--debug]     Uninstall (via amconfig)
                                        --amd also wipes active vin/ (build-output/vin or upa/vin)
                                        -n is a dry run
                                        --debug is verbose
am --version | -V                       Print version
am --help    | -h                       Brief help
am --upaupa                             Full help page

GLOBAL FLAGS
  --output=<path>                       Write output to file (JSON format)

EXIT CODES
  0  success
  1  validation error (bad name, prefix violation, reserved name, ...)
  2  not found (unknown project or gid)
  3  data error (DB corruption / unreachable)
```

## Upgrade notes

If you upgrade from a pre-projects version of `am`, your existing entries are
automatically reparented into a project called `default` on first launch.
You can use it, or `am project delete default` once you've moved the entries
to projects you create.

Brand-new installs auto-create the `upa` project on first launch. Additional
projects are created with `am project <name>`.

## Data

- Database file: `build-output/vin/am.db` (fallback: `upa/vin/am.db`; SQLite, WAL mode)
- Error log: `build-output/vin/errors.log` (fallback: `upa/vin/errors.log`)
- Corruption marker (transient): `build-output/vin/.am_corrupt` (fallback: `upa/vin/.am_corrupt`)

## Viewer

`build-output/viewer.html` (fallback: `upa/viewer.html`) is a standalone event
viewer generated by `amconfig`. Open it in any browser to inspect your `am.db`.
