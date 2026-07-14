#!/usr/bin/env bash
# pw-link.sh - MOTU M4 (Line5 stereo) → Schiit Unison Modius E

set -euo pipefail

# ================== CONFIG ==================
VOL_SOURCE="M Series 0"
INPUT_NAME="Line5"
SINK_NAME="Schiit"
VOLUME_BOOST="2.0"

LOG_LEVEL=0
DRY_RUN=false
ACTION="start"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    (( level > LOG_LEVEL )) && return
    case $level in
        0) echo -e "${RED}ERROR:${NC} $*" >&2 ;;
        1) echo -e "${GREEN}INFO:${NC}  $*" ;;
        2) echo -e "${BLUE}DEBUG:${NC} $*" ;;
    esac
}

run() {
    log 2 "→ $*"
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi
    "$@"
}

# ================== ARG PARSING ==================
while [[ $# -gt 0 ]]; do
    case $1 in
        start|stop|clear) ACTION="$1" ;;
        -v|--verbose) LOG_LEVEL=1 ;;
        -d|--debug)   LOG_LEVEL=2 ;;
        --dry-run)    DRY_RUN=true ;;
        --vol-source) VOL_SOURCE="$2"; shift ;;
        --input)      INPUT_NAME="$2"; shift ;;
        --sink)       SINK_NAME="$2";  shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [start|clear|stop] [-v] [-d] [--dry-run]"
            exit 0 ;;
        *) log 0 "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

[[ $ACTION == "clear" ]] && ACTION="stop"

# ================== HELPERS ==================
get_source_id() {
    local out
    out=$(wpctl status 2>/dev/null || true)
    local id
    id=$(echo "$out" | awk '
        /Sources:/ {in_sources=1}
        in_sources && /'"${VOL_SOURCE}"'/ {
            gsub(/[^0-9.]/, "", $0)   # keep only digits and dots
            gsub(/\..*/, "", $0)      # remove everything after first dot
            print $0
            exit
        }
    ')
    if [[ -z "$id" ]]; then
        log 0 "Could not find source ID for '${VOL_SOURCE}'"
        log 1 "Relevant lines from wpctl status:"
        echo "$out" | grep -E "(Sources:|${VOL_SOURCE})" | sed 's/^/  /' >&2
        exit 1
    fi
    log 1 "Found source ID: ${id} (${VOL_SOURCE})"
    echo "$id"
}

get_ports() {
    local out_text in_text
    out_text=$(pw-link -o 2>/dev/null || true)
    in_text=$(pw-link -i 2>/dev/null || true)

    local input_l input_r output_l output_r

    input_l=$(echo "$out_text" | grep -i "${INPUT_NAME}" | grep -i "capture_FL" | head -n1 | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//')
    input_r=$(echo "$out_text" | grep -i "${INPUT_NAME}" | grep -i "capture_FR" | head -n1 | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//')
    output_l=$(echo "$in_text" | grep -i "${SINK_NAME}" | grep -i "playback_FL" | head -n1 | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//')
    output_r=$(echo "$in_text" | grep -i "${SINK_NAME}" | grep -i "playback_FR" | head -n1 | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//')

    if [[ -z $input_l || -z $input_r || -z $output_l || -z $output_r ]]; then
        log 0 "Could not find required ports"
        (( LOG_LEVEL >= 1 )) && {
            log 1 "=== Capture ports ==="
            echo "$out_text" | grep -i capture | sed 's/^/  /'
            log 1 "=== Playback ports ==="
            echo "$in_text" | grep -i playback | sed 's/^/  /'
        }
        exit 1
    fi

    log 1 "Using ports:"
    log 1 "  In L  → $input_l"
    log 1 "  In R  → $input_r"
    log 1 "  Out L → $output_l"
    log 1 "  Out R → $output_r"

    echo "$input_l|$input_r|$output_l|$output_r"
}

# True only if $1 is linked to $2 (either direction shown by pw-link -l)
link_exists() {
    local a="$1" b="$2"
    pw-link -l 2>/dev/null | awk -v a="$a" -v b="$b" '
        $0 ~ a { linked=1; next }
        linked && $0 ~ b { found=1; exit }
        /^[^[:space:]]/ { linked=0 }
        END { exit !found }
    '
}

# ================== MAIN ==================
log 1 "=== ${ACTION^}ing audio loopback ==="

if [[ $ACTION == "start" ]]; then
    id=$(get_source_id)
    run wpctl set-volume "$id" "$VOLUME_BOOST"
    log 1 "Volume boosted to 200%"
fi

IFS='|' read -r input_l input_r output_l output_r < <(get_ports)

for side in left right; do
    [[ $side == left ]] && in_port="$input_l" out_port="$output_l" || in_port="$input_r" out_port="$output_r"

    if [[ $ACTION == "start" ]]; then
        if link_exists "$in_port" "$out_port"; then
            log 1 "${side^} link already exists"
        else
            run pw-link "$in_port" "$out_port"
            log 1 "${side^} link created"
        fi
    else
        if link_exists "$in_port" "$out_port"; then
            run pw-link -d "$in_port" "$out_port"
            log 1 "${side^} link removed"
        else
            log 1 "${side^} link does not exist"
        fi
    fi
done

log 1 "Loopback ${ACTION} complete."
