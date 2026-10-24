#!/usr/bin/env bash
# Remote commands are built locally on purpose (paths expand client side):
# shellcheck disable=SC2029

set -euo pipefail

# ==================== CONFIG ====================
REMOTE_HOST="rsync"
REMOTE_BACKUP_ROOT="/mnt/vg1000-lv/backups/$(hostnamectl hostname)"
EXCLUDE_DIRS=(
    # === General large dirs ===
    "docker/ollama/ollama/id_ed25519"
    "docker/ollama/ollama/models"
    "docker/ollama/open-webui/cache/embedding/models"
    "downloads"
    "go"
    "repos/**/src"
    "repos/**/pkg"
    "sync"
    "temp"
    ".cache"
    ".cargo"
    ".cmake"

    # === Shell / dotfiles ===
    ".bash_history"
    ".bash_logout"
    ".bash_profile"
    ".bashrc"
    "documents/age.key"

    # === Browser caches - Brave (wildcards for all profiles) ===
    ".config/BraveSoftware/Brave-Browser/**/AutofillStrikeDatabase"
    ".config/BraveSoftware/Brave-Browser/**/BudgetDatabase"
    ".config/BraveSoftware/Brave-Browser/**/chrome_cart_db"
    ".config/BraveSoftware/Brave-Browser/**/ClientCertificates"
    ".config/BraveSoftware/Brave-Browser/**/commerce_subscription_db"
    ".config/BraveSoftware/Brave-Browser/**/discount_infos_db"
    ".config/BraveSoftware/Brave-Browser/**/discounts_db"
    ".config/BraveSoftware/Brave-Browser/**/DNR Extension Rules"
    ".config/BraveSoftware/Brave-Browser/**/Download Service"
    ".config/BraveSoftware/Brave-Browser/**/Extension Scripts"
    ".config/BraveSoftware/Brave-Browser/**/Feature Engagement Tracker"
    ".config/BraveSoftware/Brave-Browser/**/GCM Store"
    ".config/BraveSoftware/Brave-Browser/**/parcel_tracking_db"
    ".config/BraveSoftware/Brave-Browser/**/PersistentOriginTrials"
    ".config/BraveSoftware/Brave-Browser/**/Platform Notifications"
    ".config/BraveSoftware/Brave-Browser/**/Service Worker/Database"
    ".config/BraveSoftware/Brave-Browser/**/Service Worker/ScriptCache"
    ".config/BraveSoftware/Brave-Browser/**/Sessions"
    ".config/BraveSoftware/Brave-Browser/**/shared_proto_db"
    ".config/BraveSoftware/Brave-Browser/**/Sync Extension Settings"
    ".config/BraveSoftware/Brave-Browser/**/Site Characteristics Database"
    ".config/BraveSoftware/Brave-Browser/**/VideoDecodeStats"

    ".config/BraveSoftware/Brave-Browser/BrowserMetrics"
    ".config/BraveSoftware/Brave-Browser/CertificateRevocation"
    ".config/BraveSoftware/Brave-Browser/component_crx_cache"
    ".config/BraveSoftware/Brave-Browser/Crash Reports"
    ".config/BraveSoftware/Brave-Browser/Crowd Deny"
    ".config/BraveSoftware/Brave-Browser/DeferredBrowserMetrics"
    ".config/BraveSoftware/Brave-Browser/Safe Browsing"
    ".config/BraveSoftware/Brave-Browser/AdBlock Custom Resources"

    # === Chromium (all profiles) ===
    ".config/chromium/**/OptimizationHints"
    ".config/chromium/**/Feature Engagement Tracker"
    ".config/chromium/**/Site Characteristics Database"
    ".config/chromium/**/ActorSafetyLists"
    ".config/chromium/**/AutofillAiModelCache"
    ".config/chromium/**/AutofillStrikeDatabase"
    ".config/chromium/**/BudgetDatabase"
    ".config/chromium/**/chrome_cart_db"
    ".config/chromium/**/ClientCertificates"
    ".config/chromium/**/commerce_subscription_db"
    ".config/chromium/**/discount_infos_db"
    ".config/chromium/**/discounts_db"
    ".config/chromium/**/DNR Extension Rules"
    ".config/chromium/**/Download Service"
    ".config/chromium/**/GCM Store"
    ".config/chromium/**/optimization_guide_hint_cache_store"
    ".config/chromium/**/parcel_tracking_db"
    ".config/chromium/**/PersistentOriginTrials"
    ".config/chromium/**/Platform Notifications"
    ".config/chromium/**/Segmentation Platform"
    ".config/chromium/**/shared_proto_db"
    ".config/chromium/CertificateRevocation"
    ".config/chromium/component_crx_cache"
    ".config/chromium/Safe Browsing"
    ".config/chromium/**/Crowd Deny"
    ".config/chromium/**/WidevineCdm"

    # === Discord ===
    ".config/discord/DawnGraphiteCache"
    ".config/discord/DawnWebGPUCache"
    ".config/discord/sentry"
    ".config/discord/app-*/"
    ".config/discord/download/"
    ".config/discord/Cache"
    ".config/discord/Code Cache"

    # === VSCodium ===
    ".config/VSCodium/**/CachedData"
    ".config/VSCodium/**/Service Worker"
    ".config/VSCodium/User/History"
    ".config/VSCodium/User/workspaceStorage"
    ".config/VSCodium/Backups/"
    ".config/VSCodium/Local Storage/"
    ".config/VSCodium/globalStorage/"

    # === Other apps ===
    ".config/Element/EventStore"
    ".config/Element/Cache"
    ".config/Element/VideoDecodeStats"
    ".config/Element/shared_proto_db"
    ".thunderbird/*/Cache"
    ".thunderbird/*/datareporting"
    ".thunderbird/*/startupCache"
    ".local/share/ranger/"
    ".oh-my-zsh/cache/"
    ".wine"

    # === General caches (very effective broad patterns) ===
    "**/blob_storage"
    "**/Cache"
    "**/Code Cache"
    "**/GPUCache"
    "**/GPUPersistentCache"
    "**/IndexedDB"
    "**/Service Worker/CacheStorage"
    "**/Session Storage"
    "**/Local Storage/leveldb"

    # === Misc junk ===
    ".config/**/SingletonCookie"
    ".config/**/SingletonLock"
    ".config/**/SingletonSocket"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".docker"
    ".dotnet"
    ".fastboot"
    ".gnupg"
    ".go"
    ".gradle"
    ".grok/marketplace-cache"
    ".grok/sessions"
    ".gsutil"
    ".java"
    ".kube/cache"
    ".lesshst"
    ".local/share/kactivitymanagerd"
    ".local/share/klipper/data"
    ".local/share/libkunitconversion"
    ".local/share/locale"
    ".local/share/Steam"
    ".local/share/Trash"
    ".local/share/yarn"
    ".local/state"
    ".mcli"
    ".mono"
    ".mozilla"
    ".npm"
    ".nuget"
    ".oh-my-zsh/log"
    ".paradoxlauncher"
    ".pki"
    ".platformio"
    ".pulse-cookie"
    ".rustup"
    ".var"
    ".vcpkg"
    ".wget-hsts"
    ".yarn"
    ".yarnrc"
    ".zcompdump-*"
)
MAX_AGE_DAYS=15
MAX_BACKUP_SIZE_GB=250
MIN_BACKUPS=2
MIN_FREE_SPACE_MB=1024
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

HOSTNAME="$(hostnamectl hostname)"

# SSH multiplexing
SSH_CONTROL_PATH="/tmp/ssh-control-backup-$$"
SSH_OPTS=(
    -o ControlMaster=auto
    -o "ControlPath=${SSH_CONTROL_PATH}"
    -o ControlPersist=10m
    -o BatchMode=yes
    -o ConnectTimeout=10
)

# ==================== FUNCTIONS ====================
send_gotify() {
    if ! curl -sS -f -X POST \
        -F "title=$1" \
        -F "message=$2" \
        -F "priority=${3:-5}" \
        "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" >/dev/null; then
        echo "Gotify notification failed" >&2
    fi
}

# All pruning in ONE SSH call
remote_prune() {
    ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \
        env \
        REMOTE_BACKUP_ROOT="${REMOTE_BACKUP_ROOT}" \
        MAX_BACKUP_SIZE_GB="${MAX_BACKUP_SIZE_GB}" \
        MAX_AGE_DAYS="${MAX_AGE_DAYS}" \
        MIN_BACKUPS="${MIN_BACKUPS}" \
        /usr/bin/env bash << 'EOF'
        set -euo pipefail

        ROOT="${REMOTE_BACKUP_ROOT}"
        MAX_BYTES=$(( MAX_BACKUP_SIZE_GB * 1024**3 ))
        MIN_BACKUPS=${MIN_BACKUPS:-2}

        cd "$ROOT" 2>/dev/null || exit 0

        # Age pruning (find -delete fails on non-empty dirs when -maxdepth 1)
        if (( MAX_AGE_DAYS > 0 )); then
            mapfile -t old_backups < <(
                find "$ROOT" -maxdepth 1 -type d -name "backup-*" -mtime +${MAX_AGE_DAYS} \
                    -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
            )

            if (( ${#old_backups[@]} > 0 )); then
                echo "Pruning by age (>${MAX_AGE_DAYS} days, ${#old_backups[@]} backups)"
                echo "Pruning by age (>${MAX_AGE_DAYS} days, ${#old_backups[@]} backups)" >> "${ROOT}/prune.log"
                for dir in "${old_backups[@]}"; do
                    [[ ! -d "$dir" ]] && continue
                    remaining=$(find "$ROOT" -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)
                    if (( remaining <= MIN_BACKUPS )); then
                        echo "  Keeping ${dir##*/} (min backups=${MIN_BACKUPS})"
                        echo "  Keeping ${dir##*/} (min backups=${MIN_BACKUPS})" >> "${ROOT}/prune.log"
                        break
                    fi
                    size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
                    rm -rf "$dir" 2>/dev/null || true
                    echo "  Deleted ${dir##*/} (age, $((size/1024**3)) GB)" >> "${ROOT}/prune.log"
                    echo "  Deleted ${dir##*/} (age, $((size/1024**3)) GB)"
                done
            else
                echo "No backups older than ${MAX_AGE_DAYS} days"
            fi
        fi

        # Size pruning
        total_bytes=$(du -scb backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0)

        if (( total_bytes > MAX_BYTES )); then
            echo "Pruning by size ($((total_bytes/1024**3)) GB > limit)"
            echo "Pruning by size ($((total_bytes/1024**3)) GB > limit)" >> "${ROOT}/prune.log"

            mapfile -t backups < <(find . -maxdepth 1 -type d -name "backup-*" -printf "%T@ %p\n" 2>/dev/null | sort -n | cut -d" " -f2-)

            for dir in "${backups[@]}"; do
                [[ ! -d "$dir" ]] && continue
                remaining=$(find . -maxdepth 1 -type d -name "backup-*" 2>/dev/null | wc -l)
                if (( remaining <= MIN_BACKUPS )); then
                    echo "  Stopping size prune (min backups=${MIN_BACKUPS})"
                    echo "  Stopping size prune (min backups=${MIN_BACKUPS})" >> "${ROOT}/prune.log"
                    break
                fi
                size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo 0)
                rm -rf "$dir" 2>/dev/null || true
                total_bytes=$((total_bytes - size))
                echo "  Deleted ${dir#./} (size, $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB)" >> "${ROOT}/prune.log"
                echo "  Deleted ${dir#./} (size, $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB)"
                (( total_bytes <= MAX_BYTES )) && break
            done
        else
            echo "Total size within limit ($((total_bytes/1024**3)) GB)"
        fi

        final_total=$(du -scb backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0)
        echo "FINAL_TOTAL:${final_total}"
EOF
}

# Decode rsync --itemize-changes lines for the debug log
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
        echo "=== Backup debug log: $(date '+%F %H:%M:%S') ==="
        echo "Source: $HOME"
        echo "Destination: ${NEW_BACKUP_DIR}/home/"
        [[ -n "${LINK_DEST_DISPLAY:-}" ]] && echo "Link-dest: ${LINK_DEST_DISPLAY}"
        echo ""
        echo "--- Transferred files ---"
        grep -E '^[>c][fdLDS]|^\*deleting' "$rsync_log" | while IFS= read -r line; do
            format_itemize_line "$line"
        done
    } > "$debug_log"
}

# Human-readable sizes (GB/MB/KB with 1 decimal)
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
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/backup-home.lock"
if ! flock -n 9; then
    echo "Another backup is already running" >&2
    exit 0
fi

echo "=== Backup started at $(date '+%F %H:%M:%S') ==="

EXCLUDE_FILE=$(mktemp)
RSYNC_LOG=$(mktemp)
DEBUG_LOG_FILE=$(mktemp)

trap 'rm -f "$EXCLUDE_FILE" "$RSYNC_LOG" "$DEBUG_LOG_FILE" 2>/dev/null || true
      ssh "${SSH_OPTS[@]}" -O exit "$REMOTE_HOST" 2>/dev/null || true
      rm -f "${SSH_CONTROL_PATH}"* 2>/dev/null || true' EXIT

# Start persistent SSH connection
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" exit 0 2>/dev/null || true

# Connectivity + disk space
echo "Checking remote server..."
FREE_MB=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "
    df --output=avail -m \"\$(dirname '${REMOTE_BACKUP_ROOT}')\" | tail -n1
" || echo 0)

if ! [[ "$FREE_MB" =~ ^[0-9]+$ ]] || (( FREE_MB < MIN_FREE_SPACE_MB )); then
    send_gotify "❌ Backup Failed on ${HOSTNAME}" "❌ Low space on NAS: ${FREE_MB} MB free" 10
    exit 1
fi

# Prepare new backup
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="backup-${DATE}"
NEW_BACKUP_DIR="${REMOTE_BACKUP_ROOT}/${BACKUP_NAME}"

PREV_BACKUP_DIR=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "
    find '${REMOTE_BACKUP_ROOT}' -maxdepth 1 -type d -name 'backup-*' ! -name 'backup-${DATE}' \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-
" || echo "")

ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "mkdir -p '${NEW_BACKUP_DIR}'"

LINK_DEST_ARGS=()
LINK_DEST_DISPLAY=""
if [[ -n "$PREV_BACKUP_DIR" ]] && ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "[ -d '${PREV_BACKUP_DIR}/home' ]" 2>/dev/null; then
    LINK_DEST_ARGS=(--link-dest="${PREV_BACKUP_DIR}/home/")
    LINK_DEST_DISPLAY="${PREV_BACKUP_DIR}/home/"
    echo "Using hard-link optimization from previous backup"
fi

printf '%s\n' "${EXCLUDE_DIRS[@]}" > "$EXCLUDE_FILE"

# Rsync
echo "Starting rsync..."

set +e
rsync -aH --delete --stats --info=progress2,stats2 --partial \
    --itemize-changes \
    --ignore-missing-args --delete-missing-args \
    "${LINK_DEST_ARGS[@]}" \
    --exclude-from="$EXCLUDE_FILE" \
    "$HOME/" "$REMOTE_HOST:${NEW_BACKUP_DIR}/home/" > "$RSYNC_LOG" 2>&1
rsync_exit=$?
set -e

RSYNC_OUTPUT=$(<"$RSYNC_LOG")

# Show clean stats (hide itemize lines and harmless vanished-file messages)
echo "$RSYNC_OUTPUT" | grep -Ev '^[>c][fdLDS]|^\*deleting|link_stat .* failed: No such file or directory|rsync error: some files/attrs were not transferred' | tail -n 50

if [ $rsync_exit -eq 0 ] || [ $rsync_exit -eq 23 ] || [ $rsync_exit -eq 24 ]; then
    if [ $rsync_exit -ne 0 ]; then
        echo "⚠️  Rsync completed with code $rsync_exit (some files vanished during live backup - normal & harmless)"
    fi
else
    echo "❌ Rsync failed with exit code $rsync_exit"
    send_gotify "❌ Backup Failed on ${HOSTNAME}" "❌ Rsync failed (exit code $rsync_exit)" 10
    exit 1
fi

# Extract sizes reliably
NEW_DATA_SIZE=$(echo "$RSYNC_OUTPUT" | grep -oP 'Total transferred file size:\s*\K[0-9,]+' | tr -d ',' || echo 0)
NEW_DATA_SIZE=${NEW_DATA_SIZE:-0}

# Write per-backup debug log of new/changed/deleted files
DEBUG_LOG_REMOTE="${NEW_BACKUP_DIR}/debug.log"
TRANSFERRED_FILE_COUNT=0
if (( ENABLE_DEBUG_LOG )); then
    write_debug_log "$RSYNC_LOG" "$DEBUG_LOG_FILE"
    TRANSFERRED_FILE_COUNT=$(grep -cE '^(NEW|CHANGED|DELETED|NEW DIR|NEW LINK)' "$DEBUG_LOG_FILE" || true)
    ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "cat > '${DEBUG_LOG_REMOTE}'" < "$DEBUG_LOG_FILE"
    echo "Debug log: ${DEBUG_LOG_REMOTE} (${TRANSFERRED_FILE_COUNT} entries)"
fi

# Record size for future fast pruning
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "du -sb '${NEW_BACKUP_DIR}' 2>/dev/null | cut -f1 > '${NEW_BACKUP_DIR}/.backup-size'" || true

# Pruning
echo "Pruning old backups..."
PRUNE_OUTPUT=$(remote_prune)

# Show clean pruning output
echo "$PRUNE_OUTPUT" | grep -E '^(Pruning by age|Pruning by size|No backups older|Total size within limit|  Deleted|  Keeping|  Stopping|FINAL_TOTAL:)' || true

# Reliable total size
TOTAL_SIZE=$(echo "$PRUNE_OUTPUT" | grep -oP 'FINAL_TOTAL:\K[0-9]+' || echo 0)
[[ -z "$TOTAL_SIZE" || "$TOTAL_SIZE" -eq 0 ]] && TOTAL_SIZE=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "
    cd '${REMOTE_BACKUP_ROOT}' 2>/dev/null || true
    du -scb backup-* 2>/dev/null | tail -n1 | cut -f1 || echo 0
" || echo 0)

# Update latest symlink
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "ln -sfnr '${NEW_BACKUP_DIR}' '${REMOTE_BACKUP_ROOT}/latest'"

# Success notification
SUCCESS_MSG="✅ Backup Success on ${HOSTNAME}
📍 Source: $HOME
📍 Destination: ${BACKUP_NAME}
📊 Total size: $(bytes_to_human "$TOTAL_SIZE")
📊 New/changed data: $(bytes_to_human "$NEW_DATA_SIZE")"
if (( ENABLE_DEBUG_LOG && TRANSFERRED_FILE_COUNT > 0 )); then
    SUCCESS_MSG+="
📝 Debug log: ${DEBUG_LOG_REMOTE} (${TRANSFERRED_FILE_COUNT} files)"
fi

echo -e "\n$SUCCESS_MSG"
send_gotify "Backup Success" "$SUCCESS_MSG" 4

echo "=== Backup completed at $(date '+%F %H:%M:%S') ==="
exit 0
