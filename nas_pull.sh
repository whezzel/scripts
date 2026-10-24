#!/usr/bin/env bash

set -euo pipefail

# ==================== CONFIG ====================
LOCAL_BACKUP_ROOT="/mnt/cryptbackup"
# ssh alias (~/.ssh/config); BACKUP_REMOTE_HOST overrides it for a one-off run
REMOTE_HOST="${BACKUP_REMOTE_HOST:-rsync}"
REMOTE_BACKUP_ROOT="/mnt/vg1000-lv"

# List of files/directories you want to backup
INCLUDE_PATHS=(
    "3amigos"
    "backups"
    "common"
    "esphome"
    "isos"
    "longhorn"
    "photos"
    "syncthing"
    "temp"
)

# Entries of INCLUDE_PATHS that may legitimately be empty. Every other entry
# must exist and be non-empty after the pull, otherwise the run fails (an
# unmounted or missing source would otherwise give an empty "successful"
# snapshot because of --ignore-missing-args).
ALLOW_EMPTY_PATHS=(
    "temp"
)

# Subpaths (relative to the snapshot root) that must exist and be non-empty
# after the pull. They are pulled as part of their INCLUDE_PATHS parent; the
# empty-source guard checks them in addition to the top-level entries.
REQUIRED_NONEMPTY_SUBPATHS=(
    "backups/luks-headers"
)

# Local pruning
MAX_AGE_DAYS=90
MAX_BACKUP_SIZE_GB=2000
MIN_BACKUPS=2
MIN_FREE_SPACE_MB=20480

ENABLE_DEBUG_LOG=1
GOTIFY_URL="https://gotify.whezzel.com"
# systemd --user keeps a session-long copy of the environment. Load the
# token from the same file interactive shells use so a roll takes effect
# without a logout.
if [[ -r "${HOME}/.shell/env" ]]; then
    GOTIFY_TOKEN="$(
        set +u
        # shellcheck disable=SC1091
        source "${HOME}/.shell/env"
        printf '%s' "${GOTIFY_TOKEN:-}"
    )"
fi
: "${GOTIFY_TOKEN?Error: GOTIFY_TOKEN not set}"

HOSTNAME="$(hostnamectl hostname 2>/dev/null || uname -n)"

# SSH multiplexing
SSH_CONTROL_PATH="/tmp/ssh-control-naspull-$$"
SSH_OPTS=(
    -o ControlMaster=auto
    -o "ControlPath=${SSH_CONTROL_PATH}"
    -o ControlPersist=10m
    -o BatchMode=yes
    -o ConnectTimeout=10
)

# ==================== FUNCTIONS ====================
send_gotify() {
    if ! curl -sS -f --max-time 30 -X POST \
        -F "title=$1" \
        -F "message=$2" \
        -F "priority=${3:-5}" \
        "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" >/dev/null; then
        echo "Gotify notification failed" >&2
    fi
}

# Maximum length of the error detail appended to a failure alert
ERR_MAX_CHARS=800

cap_text() {
    local t="$1"
    if (( ${#t} > ERR_MAX_CHARS )); then
        t="${t:0:ERR_MAX_CHARS}…"
    fi
    printf '%s' "$t"
}

# Reads a log on stdin and prints its last 5 rsync/ssh error lines, or its
# last 5 non-empty lines when no error line matches, capped at ERR_MAX_CHARS.
log_errors() {
    local text errs
    text=$(tr '\r' '\n' | grep -v '^[[:space:]]*$' || true)
    errs=$(grep -E '^rsync(: |: \[|.*error)|Permission denied|No such file|Connection|Host key|^ssh:' <<< "$text" | tail -n 5 || true)
    [[ -n "$errs" ]] || errs=$(tail -n 5 <<< "$text")
    cap_text "$errs"
}

# Describes the current holder of a lock file written as "PID start-time"
lock_holder() {
    local pid="" started=""
    read -r pid started 2>/dev/null < "$1" || true
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        printf 'held by PID %s, running since %s: %s' "$pid" "$started" \
            "$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-120)"
    else
        printf 'held by a process that did not record its PID'
    fi
}

# Decode rsync --itemize-changes lines
format_itemize_line() {
    local line="$1"

    if [[ "$line" =~ ^\*deleting[[:space:]]+(.*) ]]; then
        printf 'DELETED  %s\n' "${BASH_REMATCH[1]}"
        return
    fi

    if [[ "$line" =~ ^(.)([fdLDS])(.{9})[[:space:]](.*) ]]; then
        local prefix="${BASH_REMATCH[1]}"
        [[ "$prefix" == ">" || "$prefix" == "c" ]] || return
        local type="${BASH_REMATCH[2]}"
        local code="${BASH_REMATCH[3]}"
        local path="${BASH_REMATCH[4]}"
        local changes=""

        case "$type" in
            d) printf 'NEW DIR  %s\n' "$path"; return ;;
            L) printf 'NEW LINK %s\n' "$path"; return ;;
        esac

        if [[ "$code" == +++++++++ ]]; then
            printf 'NEW      %s\n' "$path"
            return
        fi

        [[ "$code" == *s* ]] && changes+="size "
        [[ "$code" == *t* ]] && changes+="time "
        [[ "$code" == *p* ]] && changes+="perms "
        [[ "$code" == *o* ]] && changes+="owner "
        [[ "$code" == *g* ]] && changes+="group "
        changes="${changes% }"
        printf 'CHANGED  %s%s\n' "$path" "${changes:+ ($changes)}"
    fi
}

write_debug_log() {
    local rsync_log="$1"
    local debug_log="$2"

    {
        echo "=== NAS Archive debug log: $(date '+%F %H:%M:%S') ==="
        echo "Source: ${REMOTE_HOST}:${REMOTE_BACKUP_ROOT}"
        echo "Destination: ${NEW_BACKUP_DIR}"
        [[ -n "${LINK_DEST_DISPLAY:-}" ]] && echo "Link-dest: ${LINK_DEST_DISPLAY}"
        echo ""
        echo "--- Transferred files ---"
        # `|| true`: a run with no changes has no itemize lines, and grep's
        # exit 1 would otherwise abort the whole script under pipefail + set -e
        { grep -E '^[>c][fdLDS]|^\*deleting' "$rsync_log" || true; } | while IFS= read -r line; do
            format_itemize_line "$line"
        done
    } > "$debug_log"
}

# Age of a snapshot in whole days, from the stamp in its name
# (backup-YYYY-MM-DD_HH-MM-SS); falls back to the directory mtime.
snapshot_age_days() {
    local name="$1" now="$2" stamp ts
    stamp="${name#backup-}"
    if [[ "$stamp" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})$ ]] &&
        ts=$(date -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s 2>/dev/null); then
        :
    else
        ts=$(stat -c %Y -- "$name" 2>/dev/null || echo "$now")
    fi
    echo $(( (now - ts) / 86400 ))
}

# Local pruning (age and size, keep at least MIN_BACKUPS, never the `latest` target).
# Only completed snapshots (backup-*) are considered; .inprogress-* never is.
local_prune() {
    local root="$1"
    local max_bytes=$(( MAX_BACKUP_SIZE_GB * 1024**3 ))
    local min_backups=${MIN_BACKUPS:-2}
    local now latest_target total_bytes=0 size name dir reason age_days count i rc=0 del_err
    local -a snaps=()
    local -A free_bytes=()

    cd "$root" 2>/dev/null || return 0
    now=$(date +%s)

    plog() { echo "$1"; echo "$1" >> "${root}/prune.log"; }

    # Finish deletions an earlier prune could not complete
    rm -rf -- .deleting-backup-* 2>/dev/null || true

    latest_target=$(readlink -e latest 2>/dev/null || true)
    latest_target="${latest_target##*/}"

    # Completed snapshots, newest first (the stamp in the name sorts chronologically)
    mapfile -t snaps < <(find . -maxdepth 1 -type d -name "backup-*" -printf '%f\n' 2>/dev/null | sort -r)
    count=${#snaps[@]}
    if (( count == 0 )); then
        echo "FINAL_TOTAL:0"
        return 0
    fi

    # ONE du pass over all snapshots, newest first. GNU du charges every inode
    # to the first path it meets, so each snapshot's figure is exactly what
    # deleting it frees once all older snapshots are gone, and the figures sum
    # to the real total. Deleting oldest-first keeps those figures valid.
    while IFS=$'\t' read -r size name; do
        free_bytes["$name"]=$size
        total_bytes=$(( total_bytes + size ))
    done < <(du -sb -- "${snaps[@]}" 2>/dev/null)

    plog "Prune: $(date '+%F %H:%M:%S') ${count} snapshots, $((total_bytes/1024**3)) GB (limit ${MAX_BACKUP_SIZE_GB} GB, max age ${MAX_AGE_DAYS} days, min ${min_backups})"

    for (( i = count - 1; i >= 0; i-- )); do
        dir="${snaps[i]}"
        reason=""
        if (( MAX_AGE_DAYS > 0 )); then
            age_days=$(snapshot_age_days "$dir" "$now")
            if (( age_days > MAX_AGE_DAYS )); then
                reason="age ${age_days}d"
            fi
        fi
        if [[ -z "$reason" ]] && (( total_bytes > max_bytes )); then
            reason="size"
        fi
        [[ -n "$reason" ]] || break

        if (( count <= min_backups )); then
            plog "  Keeping ${dir} (min backups=${min_backups})"
            break
        fi
        if [[ "$dir" == "$latest_target" ]]; then
            plog "  Keeping ${dir} (target of latest)"
            break
        fi
        if [[ -z "${free_bytes[$dir]:-}" ]]; then
            plog "  Stopping prune: no du figure for ${dir}"
            rc=1
            break
        fi

        # Rename first so a half-deleted snapshot can never look complete
        if ! del_err=$( { mv -T -- "$dir" ".deleting-${dir}" && rm -rf -- ".deleting-${dir}"; } 2>&1 ); then
            plog "  Stopping prune: failed to delete ${dir}: $(tail -n 2 <<< "$del_err" | tr '\n' ' ' | cut -c1-300)"
            rc=1
            break
        fi
        size=${free_bytes[$dir]}
        count=$(( count - 1 ))
        total_bytes=$(( total_bytes - size ))
        plog "  Deleted ${dir} (${reason}, freed $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB, ${count} left)"
    done

    if (( total_bytes > max_bytes )); then
        plog "  Still over size limit: $((total_bytes/1024**3)) GB"
    else
        plog "Total size within limit ($((total_bytes/1024**3)) GB)"
    fi

    echo "FINAL_TOTAL:${total_bytes}"
    return "$rc"
}

bytes_to_human() {
    local bytes=${1:-0}
    awk -v b="$bytes" 'BEGIN {
        if (b == 0) { printf "0 B"; exit }
        units="B KB MB GB TB"
        split(units, u)
        i=1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf "%.1f %s", b, u[i]
    }'
}

# ==================== FAILURE HANDLING ====================
# Every failure notifies before the script exits non-zero:
#  - known failures call fail(), which notifies and exits 1
#  - anything else (set -e, a signal, systemd's timeout) ends in the EXIT trap,
#    which notifies only if fail() has not already done so (no double notify)
FAIL_TITLE="❌ NAS Archive Failed on ${HOSTNAME}"
NOTIFIED=0
ERR_LINE=""
ERR_CMD=""
ERR_RC=""
RSYNC_LOG=""
DEBUG_LOG_FILE=""
WORK_DIR=""

fail() {
    echo "$1" >&2
    send_gotify "$FAIL_TITLE" "$1" "${2:-10}"
    NOTIFIED=1
    exit 1
}

# shellcheck disable=SC2317,SC2329  # only invoked through the EXIT trap
on_exit() {
    local rc=$? msg
    trap - EXIT
    if [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh "${SSH_OPTS[@]}" -O exit "$REMOTE_HOST" 2>/dev/null || true
    fi
    rm -f "${SSH_CONTROL_PATH}"* ${RSYNC_LOG:+"$RSYNC_LOG"} ${DEBUG_LOG_FILE:+"$DEBUG_LOG_FILE"} 2>/dev/null || true
    if (( rc != 0 && NOTIFIED == 0 )); then
        msg="❌ Aborted unexpectedly (exit ${rc})"
        case "$rc" in
            129) msg+=": killed by SIGHUP" ;;
            130) msg+=": interrupted by SIGINT (Ctrl-C)" ;;
            143) msg+=": killed by SIGTERM (systemctl stop or TimeoutStartSec)" ;;
            *) [[ -n "$ERR_LINE" ]] && msg+=": \`${ERR_CMD}\` failed with exit ${ERR_RC} at line ${ERR_LINE}" ;;
        esac
        [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && msg+="
Work dir kept for resume: ${WORK_DIR##*/}"
        msg+="
Full output: journalctl --user -u nas-pull.service"
        echo "$msg" >&2
        send_gotify "$FAIL_TITLE" "$msg" 10
    fi
    exit "$rc"
}

set -E
trap 'ERR_RC=$?; ERR_LINE=$LINENO; ERR_CMD=$BASH_COMMAND' ERR
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ==================== MAIN ====================
# Never write into the bare mountpoint of an unmounted LUKS volume
if ! MOUNT_ERR=$(mountpoint "$LOCAL_BACKUP_ROOT" 2>&1); then
    fail "❌ ${LOCAL_BACKUP_ROOT} is not mounted: ${MOUNT_ERR:-mountpoint returned non-zero}"
fi

# Prevent concurrent runs. The lock lives on the backup volume so a manual
# run and a timer run always see the same lock.
LOCK_FILE="${LOCAL_BACKUP_ROOT}/.nas-pull.lock"
exec 9>>"$LOCK_FILE"
if ! flock -n 9; then
    fail "⚠️ Another NAS archive is already running, this run was skipped (lock ${LOCK_FILE} $(lock_holder "$LOCK_FILE"))" 5
fi
printf '%s %s\n' "$$" "$(date '+%F %H:%M:%S')" > "$LOCK_FILE"

# `latest` must be a symlink (or absent); a real file/dir would break the swap
if [[ -e "${LOCAL_BACKUP_ROOT}/latest" && ! -L "${LOCAL_BACKUP_ROOT}/latest" ]]; then
    fail "❌ ${LOCAL_BACKUP_ROOT}/latest is a $(stat -c %F "${LOCAL_BACKUP_ROOT}/latest" 2>/dev/null || echo "non-symlink"), not a symlink; fix it by hand"
fi

echo "=== NAS Backup Archive started at $(date '+%F %H:%M:%S') ==="

if ! RSYNC_LOG=$(mktemp 2>&1) || ! DEBUG_LOG_FILE=$(mktemp 2>&1); then
    TMP_ERR="${DEBUG_LOG_FILE:-$RSYNC_LOG}"
    RSYNC_LOG=""; DEBUG_LOG_FILE=""
    fail "❌ Could not create temp files (TMPDIR=${TMPDIR:-/tmp}): ${TMP_ERR}"
fi

ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" exit 0 2>/dev/null || true

# Pruning runs BEFORE the free-space check so a nearly full disk can recover by
# itself. Only completed backup-* snapshots are considered, at least
# MIN_BACKUPS are kept and the target of `latest` is never deleted.
echo "Pruning old local snapshots..."
PRUNE_WARN=""
if ! PRUNE_OUTPUT=$(local_prune "$LOCAL_BACKUP_ROOT" 2>&1); then
    PRUNE_WARN="⚠️ Pruning incomplete: $(grep -E 'Stopping prune|rm:|mv:|du:' <<< "$PRUNE_OUTPUT" | tail -n 2 | cut -c1-300 || true)
(log: ${LOCAL_BACKUP_ROOT}/prune.log)"
    echo "$PRUNE_WARN" >&2
fi
echo "$PRUNE_OUTPUT" | grep -E '^(Prune:|Total size within limit|  Deleted|  Keeping|  Stopping|  Still over|FINAL_TOTAL:)' || true
PRUNED_TOTAL=$(echo "$PRUNE_OUTPUT" | grep -oP 'FINAL_TOTAL:\K[0-9]+' || echo 0)
PRUNED_TOTAL=${PRUNED_TOTAL:-0}

# Check destination free space
DF_OUT=$(df --output=avail -m "$LOCAL_BACKUP_ROOT" 2>&1 || true)
FREE_MB=$(tail -n1 <<< "$DF_OUT")
FREE_MB="${FREE_MB// /}"
PRUNE_RESULT=$(grep -E '^(  Deleted|  Keeping|  Stopping|  Still over|Total size within limit)' <<< "$PRUNE_OUTPUT" | tail -n 3 || true)
if ! [[ "$FREE_MB" =~ ^[0-9]+$ ]]; then
    fail "❌ Could not read free space on ${LOCAL_BACKUP_ROOT}: $(cap_text "$DF_OUT")"
elif (( FREE_MB < MIN_FREE_SPACE_MB )); then
    fail "❌ Low space on desktop: ${FREE_MB} MB free on ${LOCAL_BACKUP_ROOT} after pruning (need ${MIN_FREE_SPACE_MB} MB)${PRUNE_RESULT:+
Prune result:
${PRUNE_RESULT}}${PRUNE_WARN:+
${PRUNE_WARN}}"
fi

DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="backup-${DATE}"
# Final name; it only appears once the run has fully succeeded
NEW_BACKUP_DIR="${LOCAL_BACKUP_ROOT}/${BACKUP_NAME}"
# Work dir; never matches backup-*, so it is never link-dest and never pruned
WORK_DIR="${LOCAL_BACKUP_ROOT}/.inprogress-${DATE}"

# Resume an interrupted run: its already-pulled files are reused
mapfile -t LEFTOVER_DIRS < <(find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name ".inprogress-*" -printf '%f\n' 2>/dev/null | sort -r)
if (( ${#LEFTOVER_DIRS[@]} > 0 )); then
    echo "Resuming interrupted run ${LEFTOVER_DIRS[0]} as ${WORK_DIR##*/}"
    if [[ "${LEFTOVER_DIRS[0]}" != "${WORK_DIR##*/}" ]]; then
        if ! MV_ERR=$(mv -T "${LOCAL_BACKUP_ROOT}/${LEFTOVER_DIRS[0]}" "$WORK_DIR" 2>&1); then
            fail "❌ Could not resume ${LEFTOVER_DIRS[0]} as ${WORK_DIR##*/}: ${MV_ERR}"
        fi
    fi
    if (( ${#LEFTOVER_DIRS[@]} > 1 )); then
        echo "⚠️  Older leftover work dirs left in place: ${LEFTOVER_DIRS[*]:1}" >&2
    fi
else
    if ! MKDIR_ERR=$(mkdir "$WORK_DIR" 2>&1); then
        fail "❌ Could not create ${WORK_DIR}: ${MKDIR_ERR}"
    fi
fi

# Link-dest: the snapshot `latest` points to; newest completed backup-* only if latest is missing
PREV_BACKUP_DIR=""
if [[ -L "${LOCAL_BACKUP_ROOT}/latest" ]]; then
    PREV_BACKUP_DIR=$(readlink -e "${LOCAL_BACKUP_ROOT}/latest" || true)
    if [[ ! -d "$PREV_BACKUP_DIR" || "${PREV_BACKUP_DIR##*/}" != backup-* ]]; then
        echo "⚠️  latest does not resolve to a backup-* dir, falling back" >&2
        PREV_BACKUP_DIR=""
    fi
fi
if [[ -z "$PREV_BACKUP_DIR" ]]; then
    PREV_BACKUP_DIR=$(find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name "backup-*" \
        -printf '%p\n' 2>/dev/null | sort -r | head -n1 || true)
fi

LINK_DEST_ARGS=()
LINK_DEST_DISPLAY=""
if [[ -n "$PREV_BACKUP_DIR" ]]; then
    LINK_DEST_ARGS=(--link-dest="${PREV_BACKUP_DIR}/")
    LINK_DEST_DISPLAY="$PREV_BACKUP_DIR"
    echo "Using hard-link optimization from previous backup"
fi

TOTAL_NEW_DATA=0
FAILED_PATHS=()
FAIL_DETAILS=""
VANISHED_PATHS=()

echo "Starting rsync (with --delete + hard links)..."

for rel_path in "${INCLUDE_PATHS[@]}"; do
    echo "→ Pulling ${rel_path} ..."

    remote_src="${REMOTE_HOST}:${REMOTE_BACKUP_ROOT}/${rel_path}"
    local_dest="${WORK_DIR}/"

    log_start=$(wc -l < "$RSYNC_LOG")
    set +e
    rsync -aH --delete --stats --info=progress2,stats2 --partial \
        --itemize-changes \
        --ignore-missing-args --delete-missing-args \
        "${LINK_DEST_ARGS[@]}" \
        "$remote_src" "$local_dest" >> "$RSYNC_LOG" 2>&1
    rsync_exit=$?
    set -e

    # Show summary for this path
    tail -n 30 "$RSYNC_LOG" | grep -E '^(sent |total size|files transferred|Total transferred file size)' || true

    # 0 = ok, 24 = source files vanished mid-transfer (warning only).
    # 23 (partial transfer, e.g. permission denied) and everything else is a failure.
    if [ $rsync_exit -eq 0 ] || [ $rsync_exit -eq 24 ]; then
        if [ $rsync_exit -eq 24 ]; then
            echo "  ⚠️  Some source files vanished during transfer (exit 24)"
            VANISHED_PATHS+=("$rel_path")
        fi
        new_size=$(tail -n 50 "$RSYNC_LOG" | grep -oP 'Total transferred file size:\s*\K[0-9,]+' | tr -d ',' | tail -n1 || echo 0)
        new_size=${new_size:-0}
        TOTAL_NEW_DATA=$((TOTAL_NEW_DATA + new_size))
        echo "  ✓ Done - transferred $(bytes_to_human "$new_size")"
    else
        echo "  ❌ Rsync failed for ${rel_path} (exit $rsync_exit)"
        FAILED_PATHS+=("$rel_path (exit ${rsync_exit})")
        FAIL_DETAILS+="[${rel_path}]
$(tail -n +"$((log_start + 1))" "$RSYNC_LOG" | log_errors)
"
    fi
done

if (( ${#FAILED_PATHS[@]} > 0 )); then
    fail_list=$(IFS=,; echo "${FAILED_PATHS[*]}")
    fail "❌ Rsync failed for: ${fail_list}
$(cap_text "$FAIL_DETAILS")
Work dir kept for resume: ${WORK_DIR##*/}"
fi

# Empty-source guard: every expected top-level dir (except ALLOW_EMPTY_PATHS)
# and every REQUIRED_NONEMPTY_SUBPATHS entry must exist and be non-empty
is_allowed_empty() {
    local p
    for p in "${ALLOW_EMPTY_PATHS[@]}"; do
        [[ "$p" == "$1" ]] && return 0
    done
    return 1
}
# Prints "missing" or "empty" for a path in WORK_DIR, nothing if it has content
path_state() {
    if [[ ! -d "${WORK_DIR}/$1" ]]; then
        echo "missing"
    elif [[ -z "$(find "${WORK_DIR}/$1" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        echo "empty"
    fi
}
EMPTY_PATHS=()
for rel_path in "${INCLUDE_PATHS[@]}"; do
    is_allowed_empty "$rel_path" && continue
    state=$(path_state "$rel_path")
    [[ -z "$state" ]] || EMPTY_PATHS+=("${rel_path} (${state})")
done
for rel_path in "${REQUIRED_NONEMPTY_SUBPATHS[@]}"; do
    state=$(path_state "$rel_path")
    [[ -z "$state" ]] || EMPTY_PATHS+=("${rel_path} (${state})")
done
if (( ${#EMPTY_PATHS[@]} > 0 )); then
    empty_list=$(IFS=,; echo "${EMPTY_PATHS[*]}")
    fail "❌ Missing or empty after pull (source unmounted or moved on nas01?): ${empty_list}
Work dir kept: ${WORK_DIR##*/}"
fi

# Debug log
TRANSFERRED_FILE_COUNT=0
DEBUG_LOG_PATH="${NEW_BACKUP_DIR}/debug.log"
if (( ENABLE_DEBUG_LOG )); then
    write_debug_log "$RSYNC_LOG" "$DEBUG_LOG_FILE"
    TRANSFERRED_FILE_COUNT=$(grep -cE '^(NEW|CHANGED|DELETED|NEW DIR|NEW LINK)' "$DEBUG_LOG_FILE" || true)
    if ! CP_ERR=$(cp "$DEBUG_LOG_FILE" "${WORK_DIR}/debug.log" 2>&1); then
        fail "❌ Could not write ${WORK_DIR##*/}/debug.log: ${CP_ERR}
Work dir kept for resume: ${WORK_DIR##*/}"
    fi
    echo "Debug log written: ${DEBUG_LOG_PATH} (${TRANSFERRED_FILE_COUNT} entries)"
fi

# Publish: the snapshot gets its final name only now, then `latest` is swapped atomically
if ! PUB_ERR=$(mv -T "$WORK_DIR" "$NEW_BACKUP_DIR" 2>&1); then
    fail "❌ Rsync ok but renaming ${WORK_DIR##*/} to ${BACKUP_NAME} failed: ${PUB_ERR}"
fi
WORK_DIR=""
if ! PUB_ERR=$( { ln -sfn "$BACKUP_NAME" "${LOCAL_BACKUP_ROOT}/latest.new" &&
    mv -T "${LOCAL_BACKUP_ROOT}/latest.new" "${LOCAL_BACKUP_ROOT}/latest"; } 2>&1 ); then
    fail "❌ ${BACKUP_NAME} is complete but updating latest failed: ${PUB_ERR}
latest still points at $(readlink "${LOCAL_BACKUP_ROOT}/latest" 2>/dev/null || echo "nothing"); repoint it by hand"
fi
echo "Published ${BACKUP_NAME} and updated latest"

# No second prune here: the pre-run prune of the next run enforces the limits,
# and one du pass over the whole archive per run is enough.
TOTAL_SIZE=$(( PRUNED_TOTAL + TOTAL_NEW_DATA ))

# Success
SUCCESS_MSG="✅ NAS Archive Success on ${HOSTNAME}
📍 Destination: ${LOCAL_BACKUP_ROOT}
📊 New snapshot: ${BACKUP_NAME}
📊 Total size: ~$(bytes_to_human "$TOTAL_SIZE")
📊 New/changed data: $(bytes_to_human "$TOTAL_NEW_DATA")"

if (( ENABLE_DEBUG_LOG && TRANSFERRED_FILE_COUNT > 0 )); then
    SUCCESS_MSG+="
📝 Debug log: ${DEBUG_LOG_PATH} (${TRANSFERRED_FILE_COUNT} entries)"
fi
if (( ${#VANISHED_PATHS[@]} > 0 )); then
    SUCCESS_MSG+="
⚠️ Files vanished during transfer in: $(IFS=,; echo "${VANISHED_PATHS[*]}")"
fi
if [[ -n "$PRUNE_WARN" ]]; then
    SUCCESS_MSG+="
${PRUNE_WARN}"
fi

echo -e "\n$SUCCESS_MSG"
send_gotify "NAS Archive Success" "$SUCCESS_MSG" 4

echo "=== NAS Backup Archive completed at $(date '+%F %H:%M:%S') ==="
exit 0
