#!/usr/bin/env bash
# Remote commands are built locally on purpose (paths expand client side):
# shellcheck disable=SC2029

set -euo pipefail

# ==================== CONFIG ====================
# ssh alias (~/.ssh/config); BACKUP_REMOTE_HOST overrides it for a one-off run
REMOTE_HOST="${BACKUP_REMOTE_HOST:-rsync}"
REMOTE_BACKUP_ROOT="/mnt/vg1000-lv/backups/$(hostnamectl hostname 2>/dev/null || uname -n)"
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
    ".grok/sandbox-blocked*"

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
    # .gnupg itself is backed up (keys, trustdb); only its runtime sockets and locks are skipped
    ".gnupg/S.*"
    ".gnupg/*.lock"
    ".gnupg/**/*.lock"
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
MAX_AGE_DAYS=30
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

HOSTNAME="$(hostnamectl hostname 2>/dev/null || uname -n)"

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

# Text for a failed ssh call: its exit code (255 = ssh itself failed) and stderr
ssh_error() {
    local rc="$1" file="$2" what
    if (( rc == 255 )); then
        what="ssh to ${REMOTE_HOST} failed (exit 255)"
    else
        what="remote command failed (exit ${rc})"
    fi
    printf '%s: %s' "$what" "$(log_errors < "$file")"
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

# All pruning in ONE SSH call. Only completed snapshots (backup-*) are
# considered; .inprogress-* never is, and the target of `latest` is never deleted.
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
        NOW=$(date +%s)
        RC=0

        cd "$ROOT" 2>/dev/null || exit 0

        if [[ -e latest && ! -L latest ]]; then
            echo "  Stopping prune: ${ROOT}/latest is not a symlink"
            exit 3
        fi

        plog() { echo "$1"; echo "$1" >> "${ROOT}/prune.log"; }

        # Age in whole days from the stamp in the name, mtime as fallback
        age_days() {
            local name="$1" stamp ts
            stamp="${name#backup-}"
            if [[ "$stamp" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})$ ]] &&
                ts=$(date -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s 2>/dev/null); then
                :
            else
                ts=$(stat -c %Y -- "$name" 2>/dev/null || echo "$NOW")
            fi
            echo $(( (NOW - ts) / 86400 ))
        }

        # Finish deletions an earlier prune could not complete
        rm -rf -- .deleting-backup-* 2>/dev/null || true

        LATEST_TARGET=$(readlink -e latest 2>/dev/null || true)
        LATEST_TARGET="${LATEST_TARGET##*/}"

        # Completed snapshots, newest first (the stamp in the name sorts chronologically)
        mapfile -t snaps < <(find . -maxdepth 1 -type d -name "backup-*" -printf '%f\n' 2>/dev/null | sort -r)
        count=${#snaps[@]}
        if (( count == 0 )); then
            echo "FINAL_TOTAL:0"
            exit 0
        fi

        # ONE du pass, newest first: GNU du charges each inode to the first path
        # it meets, so each figure is exactly what deleting that snapshot frees
        # once all older ones are gone, and the figures sum to the real total.
        declare -A free_bytes=()
        total_bytes=0
        while IFS=$'\t' read -r size name; do
            free_bytes["$name"]=$size
            total_bytes=$(( total_bytes + size ))
        done < <(du -sb -- "${snaps[@]}" 2>/dev/null)

        plog "Prune: $(date '+%F %H:%M:%S') ${count} snapshots, $((total_bytes/1024**3)) GB (limit ${MAX_BACKUP_SIZE_GB} GB, max age ${MAX_AGE_DAYS} days, min ${MIN_BACKUPS})"

        for (( i = count - 1; i >= 0; i-- )); do
            dir="${snaps[i]}"
            reason=""
            if (( MAX_AGE_DAYS > 0 )); then
                age=$(age_days "$dir")
                if (( age > MAX_AGE_DAYS )); then
                    reason="age ${age}d"
                fi
            fi
            if [[ -z "$reason" ]] && (( total_bytes > MAX_BYTES )); then
                reason="size"
            fi
            [[ -n "$reason" ]] || break

            if (( count <= MIN_BACKUPS )); then
                plog "  Keeping ${dir} (min backups=${MIN_BACKUPS})"
                break
            fi
            if [[ "$dir" == "$LATEST_TARGET" ]]; then
                plog "  Keeping ${dir} (target of latest)"
                break
            fi
            if [[ -z "${free_bytes[$dir]:-}" ]]; then
                plog "  Stopping prune: no du figure for ${dir}"
                RC=1
                break
            fi

            # Rename first so a half-deleted snapshot can never look complete
            if ! del_err=$( { mv -T -- "$dir" ".deleting-${dir}" && rm -rf -- ".deleting-${dir}"; } 2>&1 ); then
                plog "  Stopping prune: failed to delete ${dir}: $(tail -n 2 <<< "$del_err" | tr '\n' ' ' | cut -c1-300)"
                RC=1
                break
            fi
            size=${free_bytes[$dir]}
            count=$(( count - 1 ))
            total_bytes=$(( total_bytes - size ))
            plog "  Deleted ${dir} (${reason}, freed $((size/1024**3)) GB, new total $((total_bytes/1024**3)) GB, ${count} left)"
        done

        if (( total_bytes > MAX_BYTES )); then
            plog "  Still over size limit: $((total_bytes/1024**3)) GB"
        else
            echo "Total size within limit ($((total_bytes/1024**3)) GB)"
        fi

        echo "FINAL_TOTAL:${total_bytes}"
        exit "$RC"
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
        [[ "$prefix" == "<" || "$prefix" == ">" || "$prefix" == "c" ]] || return
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
        # `|| true`: a run with no changes has no itemize lines, and grep's
        # exit 1 would otherwise abort the whole script under pipefail + set -e
        { grep -E '^[<>c][fdLDS]|^\*deleting' "$rsync_log" || true; } | while IFS= read -r line; do
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

# ==================== FAILURE HANDLING ====================
# Every failure notifies before the script exits non-zero:
#  - known failures call fail(), which notifies and exits 1
#  - anything else (set -e, a signal, systemd's timeout) ends in the EXIT trap,
#    which notifies only if fail() has not already done so (no double notify)
FAIL_TITLE="❌ Backup Failed on ${HOSTNAME}"
NOTIFIED=0
ERR_LINE=""
ERR_CMD=""
ERR_RC=""
ERR_FILE=""
EXCLUDE_FILE=""
RSYNC_LOG=""
DEBUG_LOG_FILE=""
WORK_NAME=""

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
    rm -f ${EXCLUDE_FILE:+"$EXCLUDE_FILE"} ${RSYNC_LOG:+"$RSYNC_LOG"} ${DEBUG_LOG_FILE:+"$DEBUG_LOG_FILE"} ${ERR_FILE:+"$ERR_FILE"} 2>/dev/null || true
    if [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh "${SSH_OPTS[@]}" -O exit "$REMOTE_HOST" 2>/dev/null || true
    fi
    rm -f "${SSH_CONTROL_PATH}"* 2>/dev/null || true
    if (( rc != 0 && NOTIFIED == 0 )); then
        msg="❌ Aborted unexpectedly (exit ${rc})"
        case "$rc" in
            129) msg+=": killed by SIGHUP" ;;
            130) msg+=": interrupted by SIGINT (Ctrl-C)" ;;
            143) msg+=": killed by SIGTERM (systemctl stop or TimeoutStartSec)" ;;
            *) [[ -n "$ERR_LINE" ]] && msg+=": \`${ERR_CMD}\` failed with exit ${ERR_RC} at line ${ERR_LINE}" ;;
        esac
        [[ -n "$WORK_NAME" ]] && msg+="
Work dir on the NAS (resumed next run): ${WORK_NAME}"
        msg+="
Full output: journalctl --user -e"
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
# Prevent concurrent runs (per-user runtime dir; /tmp only if neither exists)
LOCK_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[[ -d "$LOCK_DIR" && -w "$LOCK_DIR" ]] || LOCK_DIR="/tmp"
LOCK_FILE="${LOCK_DIR}/backup-home.lock"
exec 9>>"$LOCK_FILE"
if ! flock -n 9; then
    fail "⚠️ Another home backup is already running, this run was skipped (lock ${LOCK_FILE} $(lock_holder "$LOCK_FILE"))" 5
fi
printf '%s %s\n' "$$" "$(date '+%F %H:%M:%S')" > "$LOCK_FILE"

echo "=== Backup started at $(date '+%F %H:%M:%S') ==="

for tmp_var in EXCLUDE_FILE RSYNC_LOG DEBUG_LOG_FILE ERR_FILE; do
    if ! tmp_path=$(mktemp 2>&1); then
        fail "❌ Could not create temp files (TMPDIR=${TMPDIR:-/tmp}): ${tmp_path}"
    fi
    printf -v "$tmp_var" '%s' "$tmp_path"
done

# Start persistent SSH connection
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" exit 0 2>/dev/null || true

# Pruning runs BEFORE the free-space check so a nearly full NAS can recover by
# itself. Only completed backup-* snapshots are considered, at least
# MIN_BACKUPS are kept and the target of `latest` is never deleted.
echo "Pruning old backups..."
PRUNE_WARN=""
set +e
PRUNE_OUTPUT=$(remote_prune 2>"$ERR_FILE")
prune_exit=$?
set -e
if (( prune_exit != 0 )); then
    PRUNE_WARN="⚠️ Pruning incomplete (exit ${prune_exit}): $( { grep -E 'Stopping prune' <<< "$PRUNE_OUTPUT" || true; cat "$ERR_FILE"; } | log_errors)
(log: ${REMOTE_BACKUP_ROOT}/prune.log on the NAS)"
    echo "$PRUNE_WARN" >&2
fi
echo "$PRUNE_OUTPUT" | grep -E '^(Prune:|Total size within limit|  Deleted|  Keeping|  Stopping|  Still over|FINAL_TOTAL:)' || true
PRUNED_TOTAL=$(echo "$PRUNE_OUTPUT" | grep -oP 'FINAL_TOTAL:\K[0-9]+' || echo 0)
PRUNED_TOTAL=${PRUNED_TOTAL:-0}

# Connectivity + disk space
echo "Checking remote server..."
set +e
FREE_MB=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "
    df --output=avail -m \"\$(dirname '${REMOTE_BACKUP_ROOT}')\" | tail -n1
" 2>"$ERR_FILE")
df_exit=$?
set -e
if (( df_exit != 0 )); then
    fail "❌ Cannot check free space on ${REMOTE_HOST}: $(ssh_error "$df_exit" "$ERR_FILE")"
fi
FREE_MB="${FREE_MB// /}"
PRUNE_RESULT=$(grep -E '^(  Deleted|  Keeping|  Stopping|  Still over|Total size within limit)' <<< "$PRUNE_OUTPUT" | tail -n 3 || true)
if ! [[ "$FREE_MB" =~ ^[0-9]+$ ]]; then
    fail "❌ Could not read free space on the NAS: df printed '$(cap_text "$FREE_MB")'$( [[ -s "$ERR_FILE" ]] && printf '\n%s' "$(log_errors < "$ERR_FILE")")"
elif (( FREE_MB < MIN_FREE_SPACE_MB )); then
    fail "❌ Low space on NAS: ${FREE_MB} MB free after pruning (need ${MIN_FREE_SPACE_MB} MB)${PRUNE_RESULT:+
Prune result:
${PRUNE_RESULT}}${PRUNE_WARN:+
${PRUNE_WARN}}"
fi

# Prepare new backup
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="backup-${DATE}"
# Final name; it only appears on nas01 once the run has fully succeeded
NEW_BACKUP_DIR="${REMOTE_BACKUP_ROOT}/${BACKUP_NAME}"
# Work dir; never matches backup-*, so it is never link-dest and never pruned
WORK_DIR="${REMOTE_BACKUP_ROOT}/.inprogress-${DATE}"

# One SSH call: check `latest`, resume a leftover work dir (or create a new one)
# and print the link-dest snapshot (latest's target, else newest backup-*).
set +e
PREV_BACKUP_DIR=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \
    env \
    REMOTE_BACKUP_ROOT="${REMOTE_BACKUP_ROOT}" \
    WORK_NAME="${WORK_DIR##*/}" \
    /usr/bin/env bash 2>"$ERR_FILE" << 'EOF'
    set -euo pipefail
    mkdir -p "$REMOTE_BACKUP_ROOT"
    cd "$REMOTE_BACKUP_ROOT"
    if [[ -e latest && ! -L latest ]]; then
        echo "${REMOTE_BACKUP_ROOT}/latest exists but is not a symlink" >&2
        exit 3
    fi
    leftover=$(find . -maxdepth 1 -type d -name ".inprogress-*" -printf '%f\n' | sort -r | head -n1 || true)
    if [[ -n "$leftover" ]]; then
        echo "Resuming interrupted run ${leftover} as ${WORK_NAME}" >&2
        [[ "$leftover" == "$WORK_NAME" ]] || mv -T "$leftover" "$WORK_NAME"
    else
        mkdir "$WORK_NAME"
    fi
    prev=$(readlink -e latest 2>/dev/null || true)
    if [[ ! -d "$prev" || "${prev##*/}" != backup-* ]]; then
        prev=$(find "$REMOTE_BACKUP_ROOT" -maxdepth 1 -type d -name "backup-*" -printf '%p\n' | sort -r | head -n1 || true)
    fi
    printf '%s\n' "$prev"
EOF
)
prep_exit=$?
set -e
cat "$ERR_FILE" >&2
if (( prep_exit == 3 )); then
    fail "❌ ${REMOTE_BACKUP_ROOT}/latest on the NAS is not a symlink, fix it by hand"
elif (( prep_exit != 0 )); then
    fail "❌ Could not prepare the backup dir on the NAS: $(ssh_error "$prep_exit" "$ERR_FILE")"
fi
WORK_NAME="${WORK_DIR##*/}"

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
    "$HOME/" "$REMOTE_HOST:${WORK_DIR}/home/" > "$RSYNC_LOG" 2>&1
rsync_exit=$?
set -e

RSYNC_OUTPUT=$(<"$RSYNC_LOG")

# Show clean stats (hide itemize lines and harmless vanished-file messages)
echo "$RSYNC_OUTPUT" | grep -Ev '^[<>c][fdLDS]|^\*deleting|link_stat .* failed: No such file or directory|rsync error: some files/attrs were not transferred' | tail -n 50 || true

# 0 = ok, 24 = files vanished during the live backup (normal, warning only).
# 23 (partial transfer: permission denied, unreadable files, ...) and anything
# else is a failure. The work dir stays on nas01 and the next run resumes it.
VANISHED_WARN=""
if [ $rsync_exit -eq 0 ] || [ $rsync_exit -eq 24 ]; then
    if [ $rsync_exit -eq 24 ]; then
        echo "⚠️  Rsync completed with code 24 (some files vanished during live backup - normal & harmless)"
        VANISHED_WARN="⚠️ Some files vanished during transfer (exit 24)"
    fi
else
    echo "❌ Rsync failed with exit code $rsync_exit"
    if [ $rsync_exit -eq 23 ]; then
        grep -E 'Permission denied|failed:' "$RSYNC_LOG" | head -n 20 >&2 || true
    fi
    fail "❌ Rsync failed (exit code $rsync_exit)
$(log_errors < "$RSYNC_LOG")
Work dir kept for resume: ${WORK_NAME}"
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
    set +e
    ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "cat > '${WORK_DIR}/debug.log'" < "$DEBUG_LOG_FILE" 2>"$ERR_FILE"
    dbg_exit=$?
    set -e
    if (( dbg_exit != 0 )); then
        fail "❌ Could not write ${WORK_NAME}/debug.log on the NAS: $(ssh_error "$dbg_exit" "$ERR_FILE")
Work dir kept for resume: ${WORK_NAME}"
    fi
    echo "Debug log: ${DEBUG_LOG_REMOTE} (${TRANSFERRED_FILE_COUNT} entries)"
fi

# Publish on nas01: final name only now, then swap `latest` atomically
set +e
ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \
    "cd '${REMOTE_BACKUP_ROOT}' && mv -T '${WORK_NAME}' '${BACKUP_NAME}' && ln -sfn '${BACKUP_NAME}' latest.new && mv -T latest.new latest" 2>"$ERR_FILE"
pub_exit=$?
set -e
if (( pub_exit != 0 )); then
    fail "❌ Rsync ok but publishing ${BACKUP_NAME} failed: $(ssh_error "$pub_exit" "$ERR_FILE")
Check ${REMOTE_BACKUP_ROOT} on the NAS"
fi
WORK_NAME=""
echo "Published ${BACKUP_NAME} and updated latest"

# No second prune here: the pre-run prune of the next run enforces the limits,
# and one du pass over the whole backup dir per run is enough.
TOTAL_SIZE=$(( PRUNED_TOTAL + NEW_DATA_SIZE ))

# Success notification
SUCCESS_MSG="✅ Backup Success on ${HOSTNAME}
📍 Source: $HOME
📍 Destination: ${BACKUP_NAME}
📊 Total size: ~$(bytes_to_human "$TOTAL_SIZE")
📊 New/changed data: $(bytes_to_human "$NEW_DATA_SIZE")"
if (( ENABLE_DEBUG_LOG && TRANSFERRED_FILE_COUNT > 0 )); then
    SUCCESS_MSG+="
📝 Debug log: ${DEBUG_LOG_REMOTE} (${TRANSFERRED_FILE_COUNT} files)"
fi
if [[ -n "$VANISHED_WARN" ]]; then
    SUCCESS_MSG+="
${VANISHED_WARN}"
fi
if [[ -n "$PRUNE_WARN" ]]; then
    SUCCESS_MSG+="
${PRUNE_WARN}"
fi

echo -e "\n$SUCCESS_MSG"
send_gotify "Backup Success" "$SUCCESS_MSG" 4

echo "=== Backup completed at $(date '+%F %H:%M:%S') ==="
exit 0
