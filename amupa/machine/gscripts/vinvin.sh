# vinvin - diff-based backup with file watching and config-based toggles
#
# Structure per target (amdcc, amc, amupa):
#   <target_root>/vinvin/
#     .upa                # config file
#     base/               # initial full snapshot
#     current/            # always latest state
#     patches/            # <hash>.patch.gz files
#     history.txt         # <hash> <timestamp> <files_changed>
#     large_files/        # versioned large files (>medium_threshold)
#     snapshots/          # restore output directory
#
# Config (.upa) defaults:
#   enabled=off
#   check_interval_seconds=5       # how often watcher polls for changes
#   cooldown_seconds=180           # quiet period before finalizing backup
#   medium_threshold_mb=20
#   large_threshold_mb=1000
#   medium_versions=3
#   large_versions=2
#   large_keep_hours=24
#   exclude=
#
# Architecture:
#   CONFIG (.upa)          - stores all settings per target
#   BACKGROUND PROCESS     - reads config, watches files, triggers backups
#   MANUAL ACTIONS         - backup, restore, list, status
#
# Usage:
#   upaupa vinvin                          Toggle background watcher (start/stop)
#   upaupa vinvin stop                     Force stop background watcher
#
#   upaupa vinvin config                   Show config for all targets
#   upaupa vinvin config <target>          Show config for one target
#   upaupa vinvin config <target> <k> <v>  Set key=value for target
#   upaupa vinvin config --all-on          Set enabled=on for all targets
#   upaupa vinvin config --all-off         Set enabled=off for all targets
#   upaupa vinvin config <target> --on     Set enabled=on for target
#   upaupa vinvin config <target> --off    Set enabled=off for target
#
#   upaupa vinvin status                   Show watcher + per-target status
#   upaupa vinvin backup <target>          Manual backup trigger
#   upaupa vinvin restore <target> [hash]  Restore to point in time
#   upaupa vinvin list <target>            List restore points

# ============================================================================
# Path helpers
# ============================================================================

_vinvin_get_paths() {
    local target="$1"
    case "$target" in
        amdcc)
            VINVIN_SOURCE="$amdcc_loc/am-mount-host/am"
            VINVIN_BASE="$amdcc_loc/vinvin"
            ;;
        amc)
            VINVIN_SOURCE="$amc_loc/amupa/amcontainer/am"
            VINVIN_BASE="$amc_loc/vinvin"
            ;;
        amupa)
            VINVIN_SOURCE="$am_loc/amupa"
            VINVIN_BASE="$am_loc/amupa/vinvin"
            ;;
        *)
            return 1
            ;;
    esac
    VINVIN_CONFIG="$VINVIN_BASE/.upa"
    VINVIN_BASE_DIR="$VINVIN_BASE/base"
    VINVIN_CURRENT="$VINVIN_BASE/current"
    VINVIN_PATCHES="$VINVIN_BASE/patches"
    VINVIN_HISTORY="$VINVIN_BASE/history.txt"
    VINVIN_LARGE="$VINVIN_BASE/large_files"
    VINVIN_SNAPSHOTS="$VINVIN_BASE/snapshots"
    VINVIN_PID="$VINVIN_BASE/.pid"
    VINVIN_LAST_CHANGE="$VINVIN_BASE/.last_change"
    VINVIN_LOG="$VINVIN_BASE/process.log"
    VINVIN_BACKUP_LOCK="$VINVIN_BASE/.backup.lock"
}

# ============================================================================
# Config management
# ============================================================================

_vinvin_default_config() {
    cat << 'EOF'
enabled=off
check_interval_seconds=5
cooldown_seconds=180
medium_threshold_mb=20
large_threshold_mb=1000
medium_versions=3
large_versions=2
large_keep_hours=24
exclude=
EOF
}

_vinvin_read_config() {
    local target="$1"
    _vinvin_get_paths "$target" || return 1
    
    if [ ! -f "$VINVIN_CONFIG" ]; then
        mkdir -p "$VINVIN_BASE"
        _vinvin_default_config > "$VINVIN_CONFIG"
    fi
    
    # Source config into current shell
    . "$VINVIN_CONFIG"
}

_vinvin_write_config() {
    local target="$1"
    local key="$2"
    local value="$3"
    
    _vinvin_get_paths "$target" || return 1
    mkdir -p "$VINVIN_BASE"
    
    if [ ! -f "$VINVIN_CONFIG" ]; then
        _vinvin_default_config > "$VINVIN_CONFIG"
    fi
    
    # Update or add key
    if grep -q "^${key}=" "$VINVIN_CONFIG" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$VINVIN_CONFIG"
    else
        echo "${key}=${value}" >> "$VINVIN_CONFIG"
    fi
}

_vinvin_is_enabled() {
    local target="$1"
    _vinvin_read_config "$target" 2>/dev/null || return 1
    [ "$enabled" = "on" ]
}

# ============================================================================
# File classification
# ============================================================================

_vinvin_is_binary() {
    local file="$1"
    if file "$file" 2>/dev/null | grep -qE 'executable|binary|data|ELF|archive|compressed'; then
        return 0
    fi
    if head -c 8192 "$file" 2>/dev/null | grep -q $'\x00'; then
        return 0
    fi
    return 1
}

_vinvin_get_file_size_mb() {
    local file="$1"
    local size_bytes
    size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    echo $((size_bytes / 1048576))
}

_vinvin_file_tier() {
    local file="$1"
    local medium_mb="$2"
    local large_mb="$3"
    local size_mb
    size_mb=$(_vinvin_get_file_size_mb "$file")
    
    if [ "$size_mb" -ge "$large_mb" ]; then
        echo "large"
    elif [ "$size_mb" -ge "$medium_mb" ]; then
        echo "medium"
    else
        echo "normal"
    fi
}

# ============================================================================
# Large file versioning
# ============================================================================

_vinvin_store_large_file() {
    local target="$1"
    local rel_path="$2"
    local file="$3"
    local tier="$4"  # medium or large
    local timestamp="$5"
    
    _vinvin_get_paths "$target"
    _vinvin_read_config "$target"
    
    local file_hash
    file_hash=$(sha256sum "$file" 2>/dev/null | cut -c1-12)
    local dest_dir="$VINVIN_LARGE/$rel_path"
    mkdir -p "$dest_dir"
    
    local version_file="$dest_dir/${file_hash}_${timestamp}"
    
    # Check if this exact version already exists
    if [ -f "$version_file" ]; then
        return 0
    fi
    
    # Copy file
    cp "$file" "$version_file"
    
    # Manage versions based on tier
    if [ "$tier" = "large" ]; then
        # Large tier: keep only 2 versions
        # Keep: current + one backup (until next change, then 24h expiry)
        local count=0
        local oldest_file=""
        local oldest_time=9999999999
        
        for f in "$dest_dir"/*; do
            [ -f "$f" ] || continue
            count=$((count + 1))
            local mtime
            mtime=$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null || echo 0)
            if [ "$mtime" -lt "$oldest_time" ]; then
                oldest_time="$mtime"
                oldest_file="$f"
            fi
        done
        
        # If more than 2, remove oldest
        while [ "$count" -gt "$large_versions" ]; do
            if [ -n "$oldest_file" ] && [ -f "$oldest_file" ]; then
                rm -f "$oldest_file"
                count=$((count - 1))
                # Find new oldest
                oldest_time=9999999999
                oldest_file=""
                for f in "$dest_dir"/*; do
                    [ -f "$f" ] || continue
                    local mtime
                    mtime=$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null || echo 0)
                    if [ "$mtime" -lt "$oldest_time" ]; then
                        oldest_time="$mtime"
                        oldest_file="$f"
                    fi
                done
            else
                break
            fi
        done
    else
        # Medium tier: keep 3 versions (initial, 24h rolling, previous)
        local count=0
        for f in "$dest_dir"/*; do
            [ -f "$f" ] || continue
            count=$((count + 1))
        done
        
        # Simple approach: keep newest N versions
        while [ "$count" -gt "$medium_versions" ]; do
            local oldest_file=""
            local oldest_time=9999999999
            for f in "$dest_dir"/*; do
                [ -f "$f" ] || continue
                local mtime
                mtime=$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null || echo 0)
                if [ "$mtime" -lt "$oldest_time" ]; then
                    oldest_time="$mtime"
                    oldest_file="$f"
                fi
            done
            if [ -n "$oldest_file" ]; then
                rm -f "$oldest_file"
                count=$((count - 1))
            else
                break
            fi
        done
    fi
}

_vinvin_cleanup_large_files() {
    local target="$1"
    _vinvin_get_paths "$target"
    _vinvin_read_config "$target"
    
    local now_epoch
    now_epoch=$(date +%s)
    local expiry_secs=$((large_keep_hours * 3600))
    
    # Find large tier files older than expiry that aren't the only copy
    find "$VINVIN_LARGE" -type f 2>/dev/null | while read -r file; do
        local dir
        dir=$(dirname "$file")
        local count=0
        for f in "$dir"/*; do
            [ -f "$f" ] || continue
            count=$((count + 1))
        done
        
        # Only cleanup if there's more than 1 version
        if [ "$count" -gt 1 ]; then
            local mtime
            mtime=$(stat -c%Y "$file" 2>/dev/null || stat -f%m "$file" 2>/dev/null || echo 0)
            local age=$((now_epoch - mtime))
            if [ "$age" -gt "$expiry_secs" ]; then
                # Check file size to determine if it's large tier
                local size_mb
                size_mb=$(_vinvin_get_file_size_mb "$file")
                if [ "$size_mb" -ge "$large_threshold_mb" ]; then
                    rm -f "$file"
                fi
            fi
        fi
    done
}

# ============================================================================
# Patch creation and application (enhanced with large file handling)
# ============================================================================

_vinvin_create_patch() {
    local target="$1"
    local old_dir="$2"
    local new_dir="$3"
    local timestamp="$4"
    # Verbose logging controlled by VINVIN_VERBOSE env var.
    # All verbose output goes to stderr so it doesn't pollute the patch stdout.
    local _verbose="${VINVIN_VERBOSE:-0}"
    _vv_log() { [ "$_verbose" = "1" ] && echo "vinvin:   $*" >&2; }
    
    _vinvin_read_config "$target"
    
    local added_files=""
    local deleted_files=""
    local changed_files=""
    local large_files=""
    
    # Build exclude pattern (parse once, not per-file)
    local exclude_pattern=""
    local -a _excl_arr=()
    if [ -n "$exclude" ]; then
        exclude_pattern="$exclude"
        IFS=',' read -ra _excl_arr <<< "$exclude_pattern"
    fi
    
    # Check if a path matches any exclude pattern. Uses pre-parsed _excl_arr
    # so we don't re-split the comma list for every file in the tree.
    _vv_is_excluded() {
        local p="$1"
        local e
        for e in "${_excl_arr[@]}"; do
            case "$p" in
                $e*) return 0 ;;
            esac
        done
        return 1
    }
    
    # Quickly compare two regular files. Hardlinked snapshots have the same
    # inode as the source: if old_file is the same inode as new_file, they
    # are byte-identical without any I/O. Falls back to cmp otherwise.
    _vv_files_differ() {
        local a="$1" b="$2"
        local ai bi
        ai=$(stat -c%i "$a" 2>/dev/null)
        bi=$(stat -c%i "$b" 2>/dev/null)
        if [ -n "$ai" ] && [ "$ai" = "$bi" ]; then
            return 1  # same inode -> identical
        fi
        # Fast path: size differs
        local as bs
        as=$(stat -c%s "$a" 2>/dev/null)
        bs=$(stat -c%s "$b" 2>/dev/null)
        if [ -n "$as" ] && [ "$as" != "$bs" ]; then
            return 0  # differ
        fi
        cmp -s "$a" "$b"
        # cmp -s: exit 0 if same, 1 if differ -> invert
        [ $? -ne 0 ]
    }
    
    _vv_log "scanning new tree: $new_dir"
    # Find all files in new (added or changed)
    while IFS= read -r -d '' file; do
        local rel_path="${file#$new_dir/}"
        
        # Check exclusions (uses hoisted _excl_arr + helper)
        if [ -n "$exclude_pattern" ] && _vv_is_excluded "$rel_path"; then
            continue
        fi
        
        local old_file="$old_dir/$rel_path"
        
        if [ ! -e "$old_file" ]; then
            # Check if large file
            local tier
            tier=$(_vinvin_file_tier "$file" "$medium_threshold_mb" "$large_threshold_mb")
            if [ "$tier" != "normal" ]; then
                large_files="$large_files $rel_path:ADD:$tier"
                _vv_log "ADD     $rel_path (large/$tier)"
                _vinvin_store_large_file "$target" "$rel_path" "$file" "$tier" "$timestamp"
            else
                added_files="$added_files $rel_path"
                _vv_log "ADD     $rel_path"
            fi
        elif _vv_files_differ "$file" "$old_file"; then
            local tier
            tier=$(_vinvin_file_tier "$file" "$medium_threshold_mb" "$large_threshold_mb")
            if [ "$tier" != "normal" ]; then
                large_files="$large_files $rel_path:CHANGE:$tier"
                _vv_log "CHANGE  $rel_path (large/$tier)"
                _vinvin_store_large_file "$target" "$rel_path" "$file" "$tier" "$timestamp"
            else
                changed_files="$changed_files $rel_path"
                _vv_log "CHANGE  $rel_path"
            fi
        fi
    done < <(find "$new_dir" -type f -print0 2>/dev/null)
    
    _vv_log "scanning old tree for deletions: $old_dir"
    # Find deleted files: in old but not new.
    # Excluded paths are stripped from new_dir before this runs (in _vinvin_backup),
    # so they naturally show up as deletions here — no special-case needed.
    while IFS= read -r -d '' file; do
        local rel_path="${file#$old_dir/}"
        local new_file="$new_dir/$rel_path"
        
        if [ ! -e "$new_file" ]; then
            deleted_files="$deleted_files $rel_path"
            if [ -n "$exclude_pattern" ] && _vv_is_excluded "$rel_path"; then
                _vv_log "DELETE  $rel_path (newly excluded)"
            else
                _vv_log "DELETE  $rel_path"
            fi
        fi
    done < <(find "$old_dir" -type f -print0 2>/dev/null)
    
    # Detect renames/moves: any deleted file whose content sha256 matches
    # an added file is treated as a MOVE. We still record it as DELETE+ADD
    # in the patch body (so apply logic stays unchanged), but in verbose mode
    # we surface the rename so the user sees what really happened.
    if [ "$_verbose" = "1" ] && [ -n "$deleted_files" ] && [ -n "$added_files" ]; then
        declare -A _del_hashes
        local d_path d_hash a_path a_hash
        for d_path in $deleted_files; do
            d_hash=$(sha256sum "$old_dir/$d_path" 2>/dev/null | cut -c1-16)
            [ -n "$d_hash" ] && _del_hashes[$d_hash]="$d_path"
        done
        for a_path in $added_files; do
            a_hash=$(sha256sum "$new_dir/$a_path" 2>/dev/null | cut -c1-16)
            if [ -n "$a_hash" ] && [ -n "${_del_hashes[$a_hash]}" ]; then
                _vv_log "MOVE    ${_del_hashes[$a_hash]} -> $a_path"
            fi
        done
        unset _del_hashes
    fi
    
    # Count changes
    local n_added=$(echo $added_files | wc -w)
    local n_deleted=$(echo $deleted_files | wc -w)
    local n_changed=$(echo $changed_files | wc -w)
    local n_large=$(echo $large_files | wc -w)
    local total=$((n_added + n_deleted + n_changed + n_large))
    
    if [ "$total" -eq 0 ]; then
        return 1
    fi
    
    # Write patch header
    echo "VINVIN_PATCH_V2"
    echo "TIMESTAMP: $timestamp"
    echo "FILES_ADDED: $n_added"
    echo "FILES_DELETED: $n_deleted"
    echo "FILES_CHANGED: $n_changed"
    echo "FILES_LARGE: $n_large"
    echo ""
    
    # Process deleted files.
    # For paths matching an exclude pattern, write a lightweight DELETE
    # marker (no content). This avoids reading + base64-encoding huge
    # cache files just to record they're gone. Restore to an older hash
    # won't bring them back, which is the correct behavior for excluded
    # paths (they're not tracked).
    for rel_path in $deleted_files; do
        echo "--- DELETE: $rel_path"
        local old_file="$old_dir/$rel_path"
        if [ -n "$exclude_pattern" ] && _vv_is_excluded "$rel_path"; then
            echo "TYPE: EXCLUDED"
            echo ""
            continue
        fi
        if _vinvin_is_binary "$old_file"; then
            echo "TYPE: BINARY"
            echo "OLD_CONTENT_BASE64:"
            base64 "$old_file"
            echo "END_BASE64"
        else
            echo "TYPE: TEXT"
            echo "OLD_CONTENT:"
            cat "$old_file"
            echo ""
            echo "END_OLD_CONTENT"
        fi
        echo ""
    done
    
    # Process added files (normal size only)
    for rel_path in $added_files; do
        echo "--- ADD: $rel_path"
        local new_file="$new_dir/$rel_path"
        if _vinvin_is_binary "$new_file"; then
            echo "TYPE: BINARY"
            echo "CONTENT_BASE64:"
            base64 "$new_file"
            echo "END_BASE64"
        else
            echo "TYPE: TEXT"
            echo "CONTENT:"
            cat "$new_file"
            echo ""
            echo "END_CONTENT"
        fi
        echo ""
    done
    
    # Process changed files (normal size only)
    for rel_path in $changed_files; do
        echo "--- CHANGE: $rel_path"
        local old_file="$old_dir/$rel_path"
        local new_file="$new_dir/$rel_path"
        
        if _vinvin_is_binary "$new_file" || _vinvin_is_binary "$old_file"; then
            echo "TYPE: BINARY"
            echo "CONTENT_BASE64:"
            base64 "$new_file"
            echo "END_BASE64"
        else
            echo "TYPE: TEXT"
            echo "DIFF:"
            diff -u "$old_file" "$new_file" 2>/dev/null || true
            echo "END_DIFF"
        fi
        echo ""
    done
    
    # Process large files (just record the change, actual file in large_files/)
    for entry in $large_files; do
        local rel_path="${entry%%:*}"
        local rest="${entry#*:}"
        local action="${rest%%:*}"
        local tier="${rest#*:}"
        echo "--- LARGE_$action: $rel_path"
        echo "TIER: $tier"
        echo "TIMESTAMP: $timestamp"
        echo ""
    done
    
    return 0
}

_vinvin_apply_patch() {
    local patch_file="$1"
    local target_dir="$2"
    local large_files_dir="$3"
    
    local temp_patch=$(mktemp)
    gunzip -c "$patch_file" > "$temp_patch" || { rm -f "$temp_patch"; return 1; }
    
    local mode="" file_path="" file_type="" collecting="" tier="" large_ts=""
    local content_file=$(mktemp)
    
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "--- DELETE: "*)
                mode="delete"
                file_path="${line#--- DELETE: }"
                ;;
            "--- ADD: "*)
                mode="add"
                file_path="${line#--- ADD: }"
                ;;
            "--- CHANGE: "*)
                mode="change"
                file_path="${line#--- CHANGE: }"
                ;;
            "--- LARGE_ADD: "*)
                mode="large_add"
                file_path="${line#--- LARGE_ADD: }"
                ;;
            "--- LARGE_CHANGE: "*)
                mode="large_change"
                file_path="${line#--- LARGE_CHANGE: }"
                ;;
            "TYPE: BINARY")
                file_type="binary"
                ;;
            "TYPE: TEXT")
                file_type="text"
                ;;
            "TIER: "*)
                tier="${line#TIER: }"
                ;;
            "TIMESTAMP: "*)
                if [ "$mode" = "large_add" ] || [ "$mode" = "large_change" ]; then
                    large_ts="${line#TIMESTAMP: }"
                fi
                ;;
            "CONTENT_BASE64:")
                collecting="content_b64"
                > "$content_file"
                ;;
            "CONTENT:")
                collecting="content"
                > "$content_file"
                ;;
            "DIFF:")
                collecting="diff"
                > "$content_file"
                ;;
            "END_BASE64")
                if [ "$collecting" = "content_b64" ]; then
                    mkdir -p "$(dirname "$target_dir/$file_path")"
                    base64 -d "$content_file" > "$target_dir/$file_path"
                fi
                collecting=""
                ;;
            "END_CONTENT")
                if [ "$collecting" = "content" ]; then
                    mkdir -p "$(dirname "$target_dir/$file_path")"
                    head -c -1 "$content_file" > "$target_dir/$file_path" 2>/dev/null || cat "$content_file" > "$target_dir/$file_path"
                fi
                collecting=""
                ;;
            "END_DIFF")
                if [ "$collecting" = "diff" ]; then
                    mkdir -p "$(dirname "$target_dir/$file_path")"
                    patch -s "$target_dir/$file_path" < "$content_file" 2>/dev/null || true
                fi
                collecting=""
                ;;
            "OLD_CONTENT:"*|"OLD_CONTENT_BASE64:"*|"END_OLD_CONTENT"*)
                if [ "$line" = "OLD_CONTENT:" ] || [ "$line" = "OLD_CONTENT_BASE64:" ]; then
                    collecting="skip"
                elif [ "$line" = "END_OLD_CONTENT" ]; then
                    collecting=""
                fi
                ;;
            "")
                # Empty line - end of section
                if [ "$mode" = "delete" ] && [ -n "$file_path" ]; then
                    rm -f "$target_dir/$file_path"
                    local parent
                    parent=$(dirname "$target_dir/$file_path")
                    while [ "$parent" != "$target_dir" ] && [ -d "$parent" ] && [ -z "$(ls -A "$parent" 2>/dev/null)" ]; do
                        rmdir "$parent" 2>/dev/null || break
                        parent=$(dirname "$parent")
                    done
                elif [ "$mode" = "large_add" ] || [ "$mode" = "large_change" ]; then
                    # Restore from large_files - find closest timestamp version
                    if [ -n "$large_files_dir" ] && [ -d "$large_files_dir/$file_path" ]; then
                        local src_file=""
                        local best_diff=999999999999
                        # Convert target timestamp (YYYYMMDD_HHMMSS) to epoch for comparison
                        local target_epoch=0
                        if [ -n "$large_ts" ]; then
                            # Parse YYYYMMDD_HHMMSS format
                            local y="${large_ts:0:4}" m="${large_ts:4:2}" d="${large_ts:6:2}"
                            local H="${large_ts:9:2}" M="${large_ts:11:2}" S="${large_ts:13:2}"
                            target_epoch=$(date -d "$y-$m-$d $H:$M:$S" +%s 2>/dev/null || echo 0)
                        fi
                        
                        # Find version with closest timestamp
                        for f in "$large_files_dir/$file_path"/*; do
                            [ -f "$f" ] || continue
                            # Extract timestamp from filename (format: hash_YYYYMMDD_HHMMSS)
                            local fname
                            fname=$(basename "$f")
                            local file_ts="${fname#*_}"  # Remove hash prefix
                            if [ -n "$file_ts" ] && [ "$target_epoch" -gt 0 ]; then
                                local fy="${file_ts:0:4}" fm="${file_ts:4:2}" fd="${file_ts:6:2}"
                                local fH="${file_ts:9:2}" fM="${file_ts:11:2}" fS="${file_ts:13:2}"
                                local file_epoch
                                file_epoch=$(date -d "$fy-$fm-$fd $fH:$fM:$fS" +%s 2>/dev/null || echo 0)
                                if [ "$file_epoch" -gt 0 ]; then
                                    local diff=$((target_epoch - file_epoch))
                                    [ "$diff" -lt 0 ] && diff=$((-diff))
                                    if [ "$diff" -lt "$best_diff" ]; then
                                        best_diff="$diff"
                                        src_file="$f"
                                    fi
                                fi
                            else
                                # Fallback: exact match or first file
                                case "$f" in
                                    *"$large_ts"*) src_file="$f"; break ;;
                                esac
                                [ -z "$src_file" ] && src_file="$f"
                            fi
                        done
                        
                        # Final fallback to latest if nothing found
                        if [ -z "$src_file" ]; then
                            src_file=$(ls -t "$large_files_dir/$file_path"/* 2>/dev/null | head -1)
                        fi
                        if [ -n "$src_file" ] && [ -f "$src_file" ]; then
                            mkdir -p "$(dirname "$target_dir/$file_path")"
                            cp "$src_file" "$target_dir/$file_path"
                        fi
                    fi
                fi
                mode=""
                file_path=""
                tier=""
                large_ts=""
                ;;
            *)
                if [ "$collecting" = "content_b64" ] || [ "$collecting" = "content" ] || [ "$collecting" = "diff" ]; then
                    echo "$line" >> "$content_file"
                fi
                ;;
        esac
    done < "$temp_patch"
    
    rm -f "$temp_patch" "$content_file"
    return 0
}

_vinvin_apply_patches_to() {
    local target="$1"
    local target_hash="$2"
    local out_dir="$3"
    
    _vinvin_get_paths "$target"
    
    if [ ! -d "$VINVIN_BASE_DIR" ]; then
        echo "vinvin: no base snapshot found" >&2
        return 1
    fi
    
    mkdir -p "$out_dir"
    cp -r "$VINVIN_BASE_DIR"/* "$out_dir/" 2>/dev/null || true
    
    if [ ! -f "$VINVIN_HISTORY" ]; then
        return 0
    fi
    
    while IFS=' ' read -r hash ts summary; do
        local patch_file="$VINVIN_PATCHES/$hash.patch.gz"
        if [ ! -f "$patch_file" ]; then
            echo "vinvin: missing patch $hash" >&2
            return 1
        fi
        
        _vinvin_apply_patch "$patch_file" "$out_dir" "$VINVIN_LARGE" || return 1
        
        if [ "$hash" = "$target_hash" ]; then
            break
        fi
    done < "$VINVIN_HISTORY"
    
    return 0
}

# ============================================================================
# Backup execution
# ============================================================================

_vinvin_backup() {
    # Parse args: first non-flag is target, recognize --verbose anywhere
    local target=""
    local verbose=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose|-v) verbose=1 ;;
            *) [ -z "$target" ] && target="$1" ;;
        esac
        shift
    done
    
    _vinvin_get_paths "$target" || {
        echo "vinvin: unknown target: $target" >&2
        return 1
    }
    
    _vv_say() { [ "$verbose" = "1" ] && echo "vinvin: $*" >&2; }
    
    # Acquire backup lock to prevent concurrent backups (which cause
    # duplicate history entries and racing partial writes).
    mkdir -p "$VINVIN_BASE"
    if [ -f "$VINVIN_BACKUP_LOCK" ]; then
        local lock_pid
        lock_pid=$(cat "$VINVIN_BACKUP_LOCK" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            _vv_say "another backup in progress (pid $lock_pid) — skipping"
            return 0
        fi
        rm -f "$VINVIN_BACKUP_LOCK"
    fi
    echo $$ > "$VINVIN_BACKUP_LOCK"
    trap 'rm -f "$VINVIN_BACKUP_LOCK"' RETURN
    
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    _vv_say "=== backup $target $timestamp ==="
    _vv_say "source: $VINVIN_SOURCE"
    
    # Create hardlink snapshot of source on the SAME filesystem as VINVIN_BASE.
    # Using -al (archive + hardlinks) makes the snapshot near-instant with
    # ~zero extra space, and the snapshot is safe to read even while other
    # programs are using the source files (this runs in the background).
    # If the source is replaced via rename (the common edit pattern), the
    # hardlink keeps pointing at the original inode — our snapshot stays
    # consistent for the duration of the diff.
    local temp_new
    temp_new=$(mktemp -d --tmpdir="$VINVIN_BASE" .snap.XXXXXX) || {
        echo "vinvin: failed to create snapshot dir" >&2
        return 1
    }
    _vv_say "creating hardlink snapshot at $temp_new"
    (
        cd "$VINVIN_SOURCE" && find . -mindepth 1 -maxdepth 1 ! -name 'vinvin' \
            -exec cp -al {} "$temp_new/" \;
    ) || {
        echo "vinvin: failed to snapshot source" >&2
        rm -rf "$temp_new"
        return 1
    }
    if [ "$verbose" = "1" ]; then
        local snap_count
        snap_count=$(find "$temp_new" -type f 2>/dev/null | wc -l)
        _vv_say "snapshot complete: $snap_count files (hardlinks, ~0 bytes)"
    fi
    
    # Strip excluded paths from the snapshot. The hardlink step above
    # links EVERY file in source (no filter), so without this step the
    # excluded files would keep ending up in current/ via the final
    # mv — and get re-detected as "newly excluded" deletions on every
    # subsequent backup. By removing them here, the deletion-detection
    # loop records them once (this run), and they're truly gone afterward.
    _vinvin_read_config "$target" 2>/dev/null
    if [ -n "$exclude" ]; then
        local -a _backup_excl_arr
        IFS=',' read -ra _backup_excl_arr <<< "$exclude"
        local _bex
        for _bex in "${_backup_excl_arr[@]}"; do
            [ -z "$_bex" ] && continue
            if [ -e "$temp_new/$_bex" ]; then
                _vv_say "stripping excluded path from snapshot: $_bex"
                rm -rf "$temp_new/$_bex"
            fi
        done
    fi
    
    # Initialize base if needed (also via hardlinks)
    if [ ! -d "$VINVIN_BASE_DIR" ]; then
        echo "vinvin: initializing base snapshot for $target..."
        mkdir -p "$VINVIN_PATCHES" "$VINVIN_LARGE"
        cp -al "$temp_new" "$VINVIN_BASE_DIR" 2>/dev/null || cp -r "$temp_new" "$VINVIN_BASE_DIR"
        cp -al "$temp_new" "$VINVIN_CURRENT" 2>/dev/null || cp -r "$temp_new" "$VINVIN_CURRENT"
        rm -rf "$temp_new"
        echo "vinvin: base initialized"
        return 0
    fi
    
    # Create patch (verbose passed via env var into _vinvin_create_patch)
    local temp_patch
    temp_patch=$(mktemp --tmpdir="$VINVIN_BASE" .patch.XXXXXX)
    _vv_say "computing diff vs current snapshot..."
    if ! VINVIN_VERBOSE="$verbose" _vinvin_create_patch "$target" "$VINVIN_CURRENT" "$temp_new" "$timestamp" > "$temp_patch"; then
        _vv_say "no changes detected"
        [ "$verbose" != "1" ] && echo "vinvin: no changes detected for $target"
        rm -rf "$temp_new" "$temp_patch"
        return 0
    fi
    
    # Validate patch has real content (non-empty + valid header)
    # This guards against empty patches getting recorded as e3b0c44298fc
    if [ ! -s "$temp_patch" ] || [ "$(head -1 "$temp_patch")" != "VINVIN_PATCH_V2" ]; then
        rm -rf "$temp_new" "$temp_patch"
        return 0
    fi
    
    # Extract summary first to also validate the counts
    local n_added n_deleted n_changed n_large
    n_added=$(grep -m1 "^FILES_ADDED:" "$temp_patch" | cut -d' ' -f2)
    n_deleted=$(grep -m1 "^FILES_DELETED:" "$temp_patch" | cut -d' ' -f2)
    n_changed=$(grep -m1 "^FILES_CHANGED:" "$temp_patch" | cut -d' ' -f2)
    n_large=$(grep -m1 "^FILES_LARGE:" "$temp_patch" | cut -d' ' -f2)
    # Default any missing counts to 0
    n_added="${n_added:-0}"
    n_deleted="${n_deleted:-0}"
    n_changed="${n_changed:-0}"
    n_large="${n_large:-0}"
    
    # Skip if all counts are 0 (shouldn't happen but defensive)
    if [ "$n_added" = "0" ] && [ "$n_deleted" = "0" ] && [ "$n_changed" = "0" ] && [ "$n_large" = "0" ]; then
        rm -rf "$temp_new" "$temp_patch"
        return 0
    fi
    
    local summary="+${n_added}/-${n_deleted}/~${n_changed}/L${n_large}"
    
    # Hash patch
    local hash
    hash=$(sha256sum "$temp_patch" | cut -c1-12)
    
    # Skip if identical to most recent history entry (duplicate)
    if [ -f "$VINVIN_HISTORY" ]; then
        local last_hash
        last_hash=$(tail -1 "$VINVIN_HISTORY" | awk '{print $1}')
        if [ "$last_hash" = "$hash" ]; then
            rm -rf "$temp_new" "$temp_patch"
            return 0
        fi
    fi
    
    # Store patch
    mkdir -p "$VINVIN_PATCHES"
    _vv_say "compressing and storing patch $hash..."
    gzip -c "$temp_patch" > "$VINVIN_PATCHES/$hash.patch.gz" || {
        echo "vinvin: failed to store patch" >&2
        rm -rf "$temp_new" "$temp_patch"
        return 1
    }
    
    # Append to history
    echo "$hash $timestamp $summary" >> "$VINVIN_HISTORY"
    
    # Promote temp_new -> current via mv (atomic, no data copied since
    # temp_new is hardlinks on the same filesystem).
    _vv_say "promoting snapshot to current/"
    local old_current_path
    old_current_path=$(mktemp -u --tmpdir="$VINVIN_BASE" .current.old.XXXXXX)
    mv "$VINVIN_CURRENT" "$old_current_path" 2>/dev/null
    mv "$temp_new" "$VINVIN_CURRENT"
    rm -rf "$old_current_path"
    
    # Cleanup
    rm -f "$temp_patch"
    
    # Cleanup old large files
    _vinvin_cleanup_large_files "$target"
    
    local patch_size
    patch_size=$(du -h "$VINVIN_PATCHES/$hash.patch.gz" | cut -f1)
    echo "vinvin: $target $hash ($summary) [$patch_size]"
}

# ============================================================================
# File watcher
# ============================================================================

_vinvin_is_running() {
    local target="$1"
    _vinvin_get_paths "$target"
    [ -f "$VINVIN_PID" ] && kill -0 "$(cat "$VINVIN_PID" 2>/dev/null)" 2>/dev/null
}

_vinvin_start() {
    local target="$1"
    
    _vinvin_get_paths "$target" || return 1
    _vinvin_read_config "$target" || return 1
    
    if [ "$enabled" != "on" ]; then
        return 0
    fi
    
    if _vinvin_is_running "$target"; then
        return 0
    fi
    
    mkdir -p "$VINVIN_BASE"
    
    # Check for orphaned start (START without END)
    if [ -f "$VINVIN_LOG" ]; then
        local last_line
        last_line=$(tail -1 "$VINVIN_LOG")
        if echo "$last_line" | grep -q "START"; then
            # Previous session didn't log END — mark as UNKNOWN
            local orphan_pid
            orphan_pid=$(echo "$last_line" | sed 's/.*pid=\([0-9]*\).*/\1/')
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] END   pid=$orphan_pid reason=UNKNOWN duration=?" >> "$VINVIN_LOG"
        fi
    fi
    
    # Start background process
    (
        local start_ts
        start_ts=$(date +"%Y-%m-%d %H:%M:%S")
        local start_epoch
        start_epoch=$(date +%s)
        local my_pid=$$
        
        # Log start
        echo "[$start_ts] START pid=$my_pid" >> "$VINVIN_LOG"
        
        # Trap signals to log when process ends
        _vinvin_log_end() {
            local end_ts
            end_ts=$(date +"%Y-%m-%d %H:%M:%S")
            local end_epoch
            end_epoch=$(date +%s)
            local duration=$((end_epoch - start_epoch))
            local mins=$((duration / 60))
            local secs=$((duration % 60))
            echo "[$end_ts] END   pid=$my_pid reason=$1 duration=${mins}m${secs}s" >> "$VINVIN_LOG"
            rm -f "$VINVIN_PID"
        }
        trap '_vinvin_log_end SIGHUP' HUP
        trap '_vinvin_log_end SIGINT' INT
        trap '_vinvin_log_end SIGTERM' TERM
        trap '_vinvin_log_end EXIT' EXIT
        
        local last_hash=""
        local cooldown_start=0
        local pending=false
        
        while true; do
            # Check if still enabled
            _vinvin_read_config "$target" 2>/dev/null
            if [ "$enabled" != "on" ]; then
                trap - HUP INT TERM EXIT
                _vinvin_log_end DISABLED
                break
            fi
            
            # Calculate current state hash (quick check)
            # Combine: total file count + hash of any files newer than last change.
            # The file count catches deletions (find -newer alone misses them).
            local current_count
            current_count=$(find "$VINVIN_SOURCE" -type f 2>/dev/null | wc -l)
            local current_newer
            current_newer=$(find "$VINVIN_SOURCE" -type f -newer "$VINVIN_LAST_CHANGE" 2>/dev/null | head -20 | md5sum | cut -c1-8)
            local current_hash="${current_count}|${current_newer}"
            
            if [ "$current_hash" != "$last_hash" ]; then
                # Change detected
                last_hash="$current_hash"
                cooldown_start=$(date +%s)
                pending=true
                touch "$VINVIN_LAST_CHANGE"
            elif [ "$pending" = true ]; then
                # Check if cooldown expired
                local now
                now=$(date +%s)
                local elapsed=$((now - cooldown_start))
                if [ "$elapsed" -ge "$cooldown_seconds" ]; then
                    # Cooldown complete, trigger backup
                    _vinvin_backup "$target" >/dev/null 2>&1
                    pending=false
                fi
            fi
            
            # Use configurable check interval
            sleep "${check_interval_seconds:-5}"
        done
    ) &
    
    echo $! > "$VINVIN_PID"
}

_vinvin_stop() {
    local target="$1"
    _vinvin_get_paths "$target"
    
    if [ -f "$VINVIN_PID" ]; then
        local pid
        pid=$(cat "$VINVIN_PID" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            # Wait up to 3 seconds for the process to actually die,
            # otherwise toggle reports "stopped" but status still
            # shows the old PID as running.
            local waited=0
            while [ $waited -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 0.1
                waited=$((waited + 1))
            done
            rm -f "$VINVIN_PID"
        fi
    fi
}

# ============================================================================
# CLI commands
# ============================================================================

# Check if any target is running
_vinvin_any_running() {
    for t in amdcc amc amupa; do
        if _vinvin_is_running "$t"; then
            return 0
        fi
    done
    return 1
}

# Toggle: start or stop background process
_vinvin_toggle() {
    if _vinvin_any_running; then
        # Stop all
        echo "vinvin: stopping..."
        for t in amdcc amc amupa; do
            _vinvin_stop "$t"
        done
        echo "vinvin: stopped"
    else
        # Start for enabled targets
        echo "vinvin: starting..."
        local started=0
        for t in amdcc amc amupa; do
            if _vinvin_is_enabled "$t"; then
                _vinvin_start "$t"
                echo "  $t: started"
                started=$((started + 1))
            else
                echo "  $t: skipped (disabled)"
            fi
        done
        if [ "$started" -eq 0 ]; then
            echo "vinvin: no targets enabled. use 'upaupa vinvin config --all-on' to enable"
        fi
    fi
}

# Force stop all
_vinvin_stop_all() {
    echo "vinvin: force stopping..."
    for t in amdcc amc amupa; do
        _vinvin_stop "$t"
    done
    echo "vinvin: done"
}

_upaupa_vinvin() {
    local cmd="$1"
    shift 2>/dev/null || true
    
    case "$cmd" in
        "")
            # Toggle background watcher + show status
            _vinvin_toggle
            echo ""
            _vinvin_show_status
            ;;
        help)
            echo "Usage: upaupa vinvin [command]"
            echo ""
            echo "Background Process:"
            echo "  (no args)               Toggle (start/stop) + show status"
            echo "  stop                    Force stop"
            echo "  status                  Show status"
            echo ""
            echo "Config:"
            echo "  config                  Show config for all targets"
            echo "  config <target>         Show config for one target"
            echo "  config <target> <k> <v> Set key=value for target"
            echo "  config --all-on         Set enabled=on for all targets"
            echo "  config --all-off        Set enabled=off for all targets"
            echo "  config <target> --on    Set enabled=on for target"
            echo "  config <target> --off   Set enabled=off for target"
            echo ""
            echo "Manual Actions:"
            echo "  backup <target> [--verbose]  Trigger backup (show per-file actions with -v)"
            echo "  restore <target> [hash]      Restore to point in time"
            echo "  list <target>                List restore points"
            echo "  show <target> [hash] [--full]  Show patch contents"
            echo ""
            echo "Targets: amdcc, amc, amupa"
            ;;
        stop)
            _vinvin_stop_all
            ;;
        status)
            _vinvin_show_status
            ;;
        config)
            _vinvin_config_cmd "$@"
            ;;
        backup)
            if [ -z "$1" ]; then
                echo "Usage: upaupa vinvin backup <amdcc|amc|amupa> [--verbose]"
                return 1
            fi
            _vinvin_backup "$@"
            ;;
        restore)
            local target="$1"
            local hash="$2"
            
            if [ -z "$target" ]; then
                echo "Usage: upaupa vinvin restore <amdcc|amc|amupa> [hash]"
                return 1
            fi
            
            _vinvin_get_paths "$target" || {
                echo "vinvin: unknown target: $target" >&2
                return 1
            }
            
            if [ ! -d "$VINVIN_BASE_DIR" ]; then
                echo "vinvin: no backups found for $target" >&2
                return 1
            fi
            
            local out_dir
            if [ -z "$hash" ]; then
                out_dir="$VINVIN_SNAPSHOTS/latest"
                rm -rf "$out_dir"
                mkdir -p "$out_dir"
                cp -r "$VINVIN_CURRENT"/* "$out_dir/" 2>/dev/null || cp -r "$VINVIN_BASE_DIR"/* "$out_dir/"
                echo "vinvin: restored latest -> $out_dir"
            elif [ "$hash" = "base" ]; then
                out_dir="$VINVIN_SNAPSHOTS/base"
                rm -rf "$out_dir"
                mkdir -p "$out_dir"
                cp -r "$VINVIN_BASE_DIR"/* "$out_dir/"
                echo "vinvin: restored base -> $out_dir"
            else
                if ! grep -q "^$hash " "$VINVIN_HISTORY" 2>/dev/null; then
                    echo "vinvin: hash '$hash' not found" >&2
                    return 1
                fi
                out_dir="$VINVIN_SNAPSHOTS/$hash"
                rm -rf "$out_dir"
                mkdir -p "$out_dir"
                _vinvin_apply_patches_to "$target" "$hash" "$out_dir" || {
                    rm -rf "$out_dir"
                    return 1
                }
                echo "vinvin: restored $hash -> $out_dir"
            fi
            ;;
        show)
            _vinvin_show_patch "$@"
            ;;
        list)
            local target="$1"
            if [ -z "$target" ]; then
                echo "Usage: upaupa vinvin list <amdcc|amc|amupa>"
                return 1
            fi
            
            _vinvin_get_paths "$target" || {
                echo "vinvin: unknown target: $target" >&2
                return 1
            }
            
            if [ ! -f "$VINVIN_HISTORY" ]; then
                if [ -d "$VINVIN_BASE_DIR" ]; then
                    echo "vinvin list $target:"
                    echo "  base (initial snapshot)"
                else
                    echo "vinvin: no backups for $target"
                fi
                return 0
            fi
            
            echo "vinvin list $target:"
            echo "  base (initial snapshot)"
            while IFS=' ' read -r hash ts summary; do
                local size="?"
                [ -f "$VINVIN_PATCHES/$hash.patch.gz" ] && size=$(du -h "$VINVIN_PATCHES/$hash.patch.gz" | cut -f1)
                echo "  $hash  $ts  $summary  [$size]"
            done < "$VINVIN_HISTORY"
            ;;
        *)
            echo "vinvin: unknown command: $cmd" >&2
            echo "Run 'upaupa vinvin help' for usage"
            return 1
            ;;
    esac
}

# Show patch contents in a readable format
_vinvin_show_patch() {
    local target="$1"
    local hash="$2"
    local mode="${3:-summary}"  # summary (default) or full
    
    # Support --full flag in any position
    case "$2" in
        --full) mode="full"; hash="" ;;
    esac
    case "$3" in
        --full) mode="full" ;;
    esac
    
    if [ -z "$target" ]; then
        echo "Usage: upaupa vinvin show <amdcc|amc|amupa> [hash] [--full]"
        echo "  Shows the most recent patch by default."
        echo "  Pass a hash to show a specific patch."
        echo "  Use --full to dump full file contents (large output)."
        return 1
    fi
    
    _vinvin_get_paths "$target" || {
        echo "vinvin: unknown target: $target" >&2
        return 1
    }
    
    if [ ! -f "$VINVIN_HISTORY" ]; then
        echo "vinvin: no history for $target" >&2
        return 1
    fi
    
    # Default to most recent if no hash given
    if [ -z "$hash" ]; then
        hash=$(tail -1 "$VINVIN_HISTORY" | awk '{print $1}')
    fi
    
    local patch_file="$VINVIN_PATCHES/$hash.patch.gz"
    if [ ! -f "$patch_file" ]; then
        echo "vinvin: patch not found: $hash" >&2
        return 1
    fi
    
    # Find the history entry for this hash (last occurrence)
    local hist_entry
    hist_entry=$(grep "^$hash " "$VINVIN_HISTORY" | tail -1)
    local ts summary
    ts=$(echo "$hist_entry" | awk '{print $2}')
    summary=$(echo "$hist_entry" | awk '{print $3}')
    
    local size
    size=$(du -h "$patch_file" | cut -f1)
    
    echo "vinvin show $target $hash"
    echo "  timestamp: $ts"
    echo "  summary:   $summary  (+added/-deleted/~changed/Llarge)"
    echo "  size:      $size"
    echo ""
    
    if [ "$mode" = "full" ]; then
        # Dump entire patch (text content included)
        zcat "$patch_file"
        return 0
    fi
    
    # Summary mode: header + grouped path list
    echo "Header:"
    zcat "$patch_file" | sed -n '1,6p' | sed 's/^/  /'
    echo ""
    
    # Group paths by action
    local deletes adds changes larges
    deletes=$(zcat "$patch_file" | grep '^--- DELETE: ' | sed 's/^--- DELETE: //')
    adds=$(zcat "$patch_file" | grep '^--- ADD: ' | sed 's/^--- ADD: //')
    changes=$(zcat "$patch_file" | grep '^--- CHANGE: ' | sed 's/^--- CHANGE: //')
    larges=$(zcat "$patch_file" | grep '^--- LARGE: ' | sed 's/^--- LARGE: //')
    
    if [ -n "$deletes" ]; then
        echo "Deleted:"
        echo "$deletes" | sed 's/^/  - /'
        echo ""
    fi
    if [ -n "$adds" ]; then
        echo "Added:"
        echo "$adds" | sed 's/^/  + /'
        echo ""
    fi
    if [ -n "$changes" ]; then
        echo "Changed:"
        echo "$changes" | sed 's/^/  ~ /'
        echo ""
    fi
    if [ -n "$larges" ]; then
        echo "Large:"
        echo "$larges" | sed 's/^/  L /'
        echo ""
    fi
    
    echo "(use --full to dump file contents)"
}

# Show status for all targets
_vinvin_show_status() {
    echo "vinvin status:"
    local any_running=false
    for t in amdcc amc amupa; do
        _vinvin_get_paths "$t"
        _vinvin_read_config "$t" 2>/dev/null
        local status="stopped"
        if _vinvin_is_running "$t"; then
            status="running (pid $(cat "$VINVIN_PID" 2>/dev/null))"
            any_running=true
        fi
        local patch_count=0
        [ -f "$VINVIN_HISTORY" ] && patch_count=$(wc -l < "$VINVIN_HISTORY")
        echo "  $t: enabled=$enabled status=$status patches=$patch_count"
    done
    echo ""
    if [ "$any_running" = true ]; then
        echo "background process: ACTIVE"
    else
        echo "background process: INACTIVE"
    fi
}

# Config command handler
_vinvin_config_cmd() {
    local arg1="$1"
    local arg2="$2"
    local arg3="$3"
    
    # No args: show all configs
    if [ -z "$arg1" ]; then
        echo "vinvin config:"
        for t in amdcc amc amupa; do
            echo ""
            echo "[$t]"
            _vinvin_get_paths "$t"
            if [ -f "$VINVIN_CONFIG" ]; then
                cat "$VINVIN_CONFIG" | sed 's/^/  /'
            else
                _vinvin_default_config | sed 's/^/  /'
            fi
        done
        return 0
    fi
    
    # --all-on / --all-off
    if [ "$arg1" = "--all-on" ]; then
        for t in amdcc amc amupa; do
            _vinvin_write_config "$t" "enabled" "on"
            echo "vinvin: $t.enabled = on"
        done
        return 0
    fi
    if [ "$arg1" = "--all-off" ]; then
        for t in amdcc amc amupa; do
            _vinvin_write_config "$t" "enabled" "off"
            echo "vinvin: $t.enabled = off"
        done
        return 0
    fi
    
    # Target specified
    local target="$arg1"
    _vinvin_get_paths "$target" || {
        echo "vinvin: unknown target: $target" >&2
        echo "Targets: amdcc, amc, amupa"
        return 1
    }
    
    # config <target> --on / --off
    if [ "$arg2" = "--on" ]; then
        _vinvin_write_config "$target" "enabled" "on"
        echo "vinvin: $target.enabled = on"
        return 0
    fi
    if [ "$arg2" = "--off" ]; then
        _vinvin_write_config "$target" "enabled" "off"
        echo "vinvin: $target.enabled = off"
        return 0
    fi
    
    # config <target> (no key) - show config
    if [ -z "$arg2" ]; then
        echo "vinvin config $target:"
        if [ -f "$VINVIN_CONFIG" ]; then
            cat "$VINVIN_CONFIG" | sed 's/^/  /'
        else
            _vinvin_default_config | sed 's/^/  /'
        fi
        return 0
    fi
    
    # config <target> <key> (no value) - show key
    if [ -z "$arg3" ]; then
        _vinvin_read_config "$target"
        eval "echo \"\$$arg2\""
        return 0
    fi
    
    # config <target> <key> <value> - set key
    _vinvin_write_config "$target" "$arg2" "$arg3"
    echo "vinvin: $target.$arg2 = $arg3"
}

