#!/usr/bin/env bash
# Fetch vnstat stats from a remote OPNsense host via SSH.
# Host user/port/etc come from ~/.ssh/config — just pass the Host alias.
# Usage: ./opnsense_vnstat.sh <host> <function> [interface]
# Example: ./opnsense_vnstat.sh opnsense today igc0

set -euo pipefail

HOST=${1:-}
FUNC=${2:-}
INTERFACE=${3:-igc0}

if [[ -z "$HOST" || -z "$FUNC" ]]; then
    echo "Usage: $0 <host> <function> [interface]"
    echo "Functions: today, yesterday, month, year, all"
    exit 1
fi

run_ssh() {
    local cmd="$1"
    ssh "$HOST" "$cmd"
}

# $1 = vnstat mode flags (-d/-m/-y), $2 = grep pattern, $3 = awk field expr
parse_total() {
    local flags=$1 pattern=$2 fields=$3
    local output
    # grep miss must not kill the script under set -o pipefail
    output=$(run_ssh "vnstat -i $(printf '%q' "$INTERFACE") ${flags}" \
        | { grep -F -- "$pattern" || true; } \
        | awk "{print ${fields}}" \
        | head -1)
    [[ -n "$output" ]] || return 1
    echo "$output"
}

today() {
    local output
    output=$(parse_total "-d" "$(date +%Y-%m-%d)" '$8"_"$9' 2>/dev/null \
        || parse_total "-d" "$(date +%D)" '$8"_"$9' 2>/dev/null \
        || true)
    [[ -n "${output:-}" ]] || { echo "No data for today." >&2; exit 1; }
    echo "$output"
}

yesterday() {
    local output
    output=$(parse_total "-d" "$(date -d yesterday +%Y-%m-%d)" '$8"_"$9' 2>/dev/null \
        || parse_total "-d" "$(date -d yesterday +%D)" '$8"_"$9' 2>/dev/null \
        || true)
    [[ -n "${output:-}" ]] || { echo "No data for yesterday." >&2; exit 1; }
    echo "$output"
}

month() {
    local output
    output=$(parse_total "-m" "$(date +%Y-%m)" '$9"_"$10' 2>/dev/null \
        || parse_total "-m" "$(date +"%b '%y")" '$9"_"$10' 2>/dev/null \
        || true)
    [[ -n "${output:-}" ]] || { echo "No data for this month." >&2; exit 1; }
    echo "$output"
}

year() {
    local output
    output=$(parse_total "-y" "$(date +%Y)" '$8"_"$9' 2>/dev/null || true)
    [[ -n "${output:-}" ]] || { echo "No data for this year." >&2; exit 1; }
    echo "$output"
}

# Extract first matching line fields; never fail under pipefail (empty = no match)
match_fields() {
    local text=$1 pattern=$2 fields=$3
    # shellcheck disable=SC2086
    echo "$text" | grep -F -- "$pattern" | awk "{print ${fields}}" | head -1 || true
}

all() {
    # One SSH: dump daily/monthly/yearly text, parse locally
    local dump daily monthly yearly
    local t y m yr
    local iface
    iface=$(printf '%q' "$INTERFACE")

    dump=$(run_ssh "vnstat -i ${iface} -d; echo '===SPLIT==='; vnstat -i ${iface} -m; echo '===SPLIT==='; vnstat -i ${iface} -y")

    daily=$(echo "$dump" | awk 'BEGIN{p=1} /^===SPLIT===$/{p++; next} p==1{print}')
    monthly=$(echo "$dump" | awk 'BEGIN{p=1} /^===SPLIT===$/{p++; next} p==2{print}')
    yearly=$(echo "$dump" | awk 'BEGIN{p=1} /^===SPLIT===$/{p++; next} p==3{print}')

    # Prefer ISO dates, fall back to locale formats vnstat often uses
    t=$(match_fields "$daily" "$(date +%Y-%m-%d)" '$8"_"$9')
    [[ -n "$t" ]] || t=$(match_fields "$daily" "$(date +%D)" '$8"_"$9')

    y=$(match_fields "$daily" "$(date -d yesterday +%Y-%m-%d)" '$8"_"$9')
    [[ -n "$y" ]] || y=$(match_fields "$daily" "$(date -d yesterday +%D)" '$8"_"$9')

    m=$(match_fields "$monthly" "$(date +%Y-%m)" '$9"_"$10')
    [[ -n "$m" ]] || m=$(match_fields "$monthly" "$(date +"%b '%y")" '$9"_"$10')

    yr=$(match_fields "$yearly" "$(date +%Y)" '$8"_"$9')

    if [[ -z "${t:-}" || -z "${y:-}" || -z "${m:-}" || -z "${yr:-}" ]]; then
        # Fall back to the individual helpers (4 SSH) if bulk parse missed something
        echo "$(today) $(yesterday) $(month) $(year)"
        return
    fi

    echo "${t} ${y} ${m} ${yr}"
}

case "$FUNC" in
    today|yesterday|month|year|all)
        "$FUNC"
        ;;
    *)
        echo "Error: Invalid function '$FUNC'. Use: today, yesterday, month, year, all" >&2
        exit 1
        ;;
esac
