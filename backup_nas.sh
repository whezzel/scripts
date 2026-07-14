#!/usr/bin/env bash

set -euo pipefail

# ==================== CONFIG ====================
LOCAL_BACKUP_ROOT="/mnt/cryptbackup"
REMOTE_HOST="rsync"
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

# Local pruning
MAX_AGE_DAYS=90
MAX_BACKUP_SIZE_GB=2000
MIN_BACKUPS=2
MIN_FREE_SPACE_MB=20480

ENABLE_DEBUG_LOG=1
GOTIFY_URL="https://gotify.whezzel.com"
: "${GOTIFY_TOKEN?Error: GOTIFY_TOKEN not set}"

HOSTNAME="$(hostnamectl hostname)"

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
    curl -s -X POST \
        -F "title=$1" \
        -F "message=$2" \
        -F "priority=${3:-5}" \
        "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" >/dev/null || true
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
        grep -E '^[>c][fdLDS]|^\*deleting' "$rsync_log" | while IFS= read -r line; do
            format_itemize_line "$line"
        done
    } > "$debug_log"
}

# Local pruning (age then size, keep at least MIN_BACKUPS)
local_prune() {
    local root="$1"
    local max_bytes=$(( MAX_BACKUP_SIZE_GB * 1024**3 ))
    local min_backups=${MIN_BACKUPS:-2}

    cd "$root" 2>/dev/null || return 0

    # Age pruning
    if (( MAX_AGE_DAYS > 0 )); then
        mapfile -t old_backups < <(
            find "$root" -maxdepth 1 -type d -name "backup-*" -mtime +${MAX_AGE_DAYS} \
                -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
        )

        if (( ${#old_backups[@]} > 0 )); then
            echo "Pruning by age (>${MAX_AGE_DAYS} days, ${#old_backups[@]} backups)" >> "${root}/prune.log"
            echo "Pruning by age (>${MAX_AGE_DAYS} days, ${#old_backups[@]} backups)"

            for dir in "${old_backups[@]}"; do
                [[ ! -d "$dir" ]] && continue
                remaining=$(find "$root" -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)
                if (( remaining <= min_backups )); then
                    echo "  Keeping ${dir##*/} (min backups=${min_backups})"
                    echo "  Keeping ${dir##*/} (min backups=${min_backups})" >> "${root}/prune.log"
                    break
                fi
                size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
                rm -rf "$dir" 2>/dev/null || true
                echo "  Deleted ${dir##*/} (age, $((size/1024**3)) GB)" >> "${root}/prune.log"
                echo "  Deleted ${dir##*/} (age, $((size/1024**3)) GB)"
            done
        else
            echo "No backups older than ${MAX_AGE_DAYS} days" >> "${root}/prune.log"
            echo "No backups older than ${MAX_AGE_DAYS} days"
        fi
    fi

    # Size pruning
    total_bytes=$(du -scb backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0)

    if (( total_bytes > max_bytes )); then
        echo "Pruning by size ($((total_bytes/1024**3)) GB > limit)" >> "${root}/prune.log"
        echo "Pruning by size ($((total_bytes/1024**3)) GB > limit)"

        mapfile -t backups < <(find . -maxdepth 1 -type d -name "backup-*" -printf "%T@ %p\n" 2>/dev/null | sort -n | cut -d" " -f2-)

        for dir in "${backups[@]}"; do
            [[ ! -d "$dir" ]] && continue
            remaining=$(find . -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)
            if (( remaining <= min_backups )); then
                echo "  Stopping size prune (min backups=${min_backups})"
                echo "  Stopping size prune (min backups=${min_backups})" >> "${root}/prune.log"
                break
            fi
            size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
            rm -rf "$dir" 2>/dev/null || true
            total_bytes=$((total_bytes - size))
            echo "  Deleted ${dir#./} (size, $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB)" >> "${root}/prune.log"
            echo "  Deleted ${dir#./} (size, $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB)"
            (( total_bytes <= max_bytes )) && break
        done
    else
        echo "Total size within limit ($((total_bytes/1024**3)) GB)" >> "${root}/prune.log"
        echo "Total size within limit ($((total_bytes/1024**3)) GB)"
    fi

    final_total=$(du -scb backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0)
    echo "FINAL_TOTAL:${final_total}"
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

# ==================== MAIN ====================
# Prevent concurrent runs
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/backup-nas.lock"
if ! flock -n 9; then
    echo "Another NAS archive is already running" >&2
    exit 0
fi

echo "=== NAS Backup Archive started at $(date '+%F %H:%M:%S') ==="

RSYNC_LOG=$(mktemp)
DEBUG_LOG_FILE=$(mktemp)

trap 'ssh "${SSH_OPTS[@]}" -O exit "$REMOTE_HOST" 2>/dev/null || true
      rm -f "${SSH_CONTROL_PATH}"* "$RSYNC_LOG" "$DEBUG_LOG_FILE" 2>/dev/null || true' EXIT

ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" exit 0 2>/dev/null || true

# Check destination free space
FREE_MB=$(df --output=avail -m "$LOCAL_BACKUP_ROOT" 2>/dev/null | tail -n1 || echo 0)
if ! [[ "$FREE_MB" =~ ^[0-9]+$ ]] || (( FREE_MB < MIN_FREE_SPACE_MB )); then
    send_gotify "❌ NAS Archive Failed on ${HOSTNAME}" "❌ Low space on desktop: ${FREE_MB} MB free" 10
    exit 1
fi

DATE=$(date +%Y-%m-%d_%H-%M-%S)
NEW_BACKUP_DIR="${LOCAL_BACKUP_ROOT}/backup-${DATE}"
mkdir -p "$NEW_BACKUP_DIR"

PREV_BACKUP_DIR=$(find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name "backup-*" ! -name "backup-${DATE}" \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || "")

LINK_DEST_ARGS=()
LINK_DEST_DISPLAY=""
if [[ -n "$PREV_BACKUP_DIR" ]]; then
    LINK_DEST_ARGS=(--link-dest="${PREV_BACKUP_DIR}/")
    LINK_DEST_DISPLAY="$PREV_BACKUP_DIR"
    echo "Using hard-link optimization from previous backup"
fi

TOTAL_NEW_DATA=0
FAILED_PATHS=()

echo "Starting rsync (with --delete + hard links)..."

for rel_path in "${INCLUDE_PATHS[@]}"; do
    echo "→ Pulling ${rel_path} ..."

    remote_src="${REMOTE_HOST}:${REMOTE_BACKUP_ROOT}/${rel_path}"
    local_dest="${NEW_BACKUP_DIR}/"

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

    if [ $rsync_exit -eq 0 ] || [ $rsync_exit -eq 23 ] || [ $rsync_exit -eq 24 ]; then
        new_size=$(tail -n 50 "$RSYNC_LOG" | grep -oP 'Total transferred file size:\s*\K[0-9,]+' | tr -d ',' | tail -n1 || echo 0)
        new_size=${new_size:-0}
        TOTAL_NEW_DATA=$((TOTAL_NEW_DATA + new_size))
        echo "  ✓ Done - transferred $(bytes_to_human "$new_size")"
    else
        echo "  ❌ Rsync failed for ${rel_path} (exit $rsync_exit)"
        FAILED_PATHS+=("$rel_path")
    fi
done

if (( ${#FAILED_PATHS[@]} > 0 )); then
    fail_list=$(IFS=,; echo "${FAILED_PATHS[*]}")
    echo "❌ One or more paths failed: ${fail_list}"
    send_gotify "❌ NAS Archive Failed on ${HOSTNAME}" \
        "❌ Rsync failed for: ${fail_list}" 10
    exit 1
fi

# Debug log
TRANSFERRED_FILE_COUNT=0
DEBUG_LOG_PATH="${NEW_BACKUP_DIR}/debug.log"
if (( ENABLE_DEBUG_LOG )); then
    write_debug_log "$RSYNC_LOG" "$DEBUG_LOG_FILE"
    TRANSFERRED_FILE_COUNT=$(grep -cE '^(NEW|CHANGED|DELETED|NEW DIR|NEW LINK)' "$DEBUG_LOG_FILE" || true)
    cp "$DEBUG_LOG_FILE" "$DEBUG_LOG_PATH"
    echo "Debug log written: ${DEBUG_LOG_PATH} (${TRANSFERRED_FILE_COUNT} entries)"
fi

# Update latest symlink
ln -sfn "backup-${DATE}" "${LOCAL_BACKUP_ROOT}/latest"

# Pruning
echo "Pruning old local snapshots..."
PRUNE_OUTPUT=$(local_prune "$LOCAL_BACKUP_ROOT")

echo "$PRUNE_OUTPUT" | grep -E '^(Pruning by age|Pruning by size|No backups older|Total size within limit|  Deleted|  Keeping|  Stopping|FINAL_TOTAL:)' || true

TOTAL_SIZE=$(echo "$PRUNE_OUTPUT" | grep -oP 'FINAL_TOTAL:\K[0-9]+' || echo 0)
[[ -z "$TOTAL_SIZE" || "$TOTAL_SIZE" -eq 0 ]] && TOTAL_SIZE=$(du -scb "$LOCAL_BACKUP_ROOT"/backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0)

# Success
SUCCESS_MSG="✅ NAS Archive Success on ${HOSTNAME}
📍 Destination: ${LOCAL_BACKUP_ROOT}
📊 New snapshot: backup-${DATE}
📊 Total size: $(bytes_to_human "$TOTAL_SIZE")
📊 New/changed data: $(bytes_to_human "$TOTAL_NEW_DATA")"

if (( ENABLE_DEBUG_LOG && TRANSFERRED_FILE_COUNT > 0 )); then
    SUCCESS_MSG+="
📝 Debug log: ${DEBUG_LOG_PATH} (${TRANSFERRED_FILE_COUNT} entries)"
fi

echo -e "\n$SUCCESS_MSG"
send_gotify "NAS Archive Success" "$SUCCESS_MSG" 4

echo "=== NAS Backup Archive completed at $(date '+%F %H:%M:%S') ==="
exit 0
