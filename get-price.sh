#!/usr/bin/env bash

# get-price.sh – gold-api.com price fetcher
# Optionally writes to InfluxDB 2.x when INFLUX_* env vars are set

set -euo pipefail

USER_AGENT="get-price.sh/2.1"

# Dependencies
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }

show_help() {
    cat <<EOF
Usage: $0 SYMBOL

  SYMBOL          Fetch price in USD (XAG, XAU, BTC, ETH, ...)

Examples:
  $0 XAG          # → 87.42 (silver)
  $0 XAU          # gold
  $0 BTC          # bitcoin

InfluxDB: Set INFLUX_HOST, INFLUX_ORG, INFLUX_BUCKET, INFLUX_TOKEN to enable writes
Source:   https://gold-api.com/docs
EOF
    exit 0
}

[[ $# -eq 1 && "$1" != -* ]] || show_help

SYMBOL="${1^^}"

# ──────────────────────────────────────────────
# Fetch price
# ──────────────────────────────────────────────
response=$(curl -s --fail --compressed \
                --connect-timeout 6 --max-time 12 --retry 2 \
                -H "User-Agent: ${USER_AGENT}" \
                -H "Accept: application/json" \
                "https://api.gold-api.com/price/${SYMBOL}")

if [[ "$response" == "Symbol not found" ]]; then
    echo "Error: Symbol '${SYMBOL}' not supported by gold-api.com" >&2
    echo "See supported symbols: https://api.gold-api.com/symbols" >&2
    exit 1
fi

price=$(echo "$response" | jq -r '.price' 2>/dev/null)

if [[ -z "$price" || "$price" == "null" ]]; then
    echo "Error: Could not parse price (invalid response)" >&2
    echo "Raw: $response" >&2
    exit 1
fi

# ──────────────────────────────────────────────
# InfluxDB 2.x write (optional)
# ──────────────────────────────────────────────
if [[ -n "${INFLUX_HOST:-}" && -n "${INFLUX_ORG:-}" && -n "${INFLUX_BUCKET:-}" && -n "${INFLUX_TOKEN:-}" ]]; then
    TIMESTAMP=$(date +%s)
    LINE="commodity_price,symbol=${SYMBOL},source=gold-api,unit=USD price=${price} ${TIMESTAMP}"

    curl --request POST \
         "${INFLUX_HOST}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}&precision=s" \
         --header "Authorization: Token ${INFLUX_TOKEN}" \
         --header "Content-Type: text/plain; charset=utf-8" \
         --header "Accept: application/json" \
         --data-binary "${LINE}" \
         --fail --silent 2>/dev/null || {
             echo "Warning: Failed to write to InfluxDB (bucket: ${INFLUX_BUCKET})" >&2
         }
fi

# Success: output only the price
echo "$price"
exit 0
