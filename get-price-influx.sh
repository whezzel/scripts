#!/usr/bin/env bash

# get-price-influx.sh – fetch latest commodity price from InfluxDB 2.x

set -euo pipefail

: "${INFLUX_HOST?Error: INFLUX_HOST not set}"
: "${INFLUX_ORG?Error: INFLUX_ORG not set}"
: "${INFLUX_BUCKET?Error: INFLUX_BUCKET not set}"
: "${INFLUX_TOKEN?Error: INFLUX_TOKEN not set}"

command -v curl >/dev/null 2>&1 || { echo "Error: curl required" >&2; exit 1; }

[[ $# -eq 1 && "$1" != -* ]] || { echo "Usage: $0 SYMBOL (e.g. XAU or XAG)" >&2; exit 1; }

SYMBOL="${1^^}"

FLUX_QUERY=$(cat <<EOF
from(bucket: "$INFLUX_BUCKET")
  |> range(start: -5d)
  |> filter(fn: (r) => r._measurement == "commodity_price")
  |> filter(fn: (r) => r.symbol == "$SYMBOL")
  |> filter(fn: (r) => r._field == "price")
  |> last()
  |> map(fn: (r) => ({ _value: string(v: r._value) }))
  |> keep(columns: ["_value"])
EOF
)

response=$(curl --silent --fail --compressed \
    --connect-timeout 8 --max-time 12 \
    "${INFLUX_HOST}/api/v2/query?org=${INFLUX_ORG}" \
    --header "Authorization: Token ${INFLUX_TOKEN}" \
    --header 'Accept: application/csv' \
    --header 'Content-type: application/vnd.flux' \
    --data "${FLUX_QUERY}") || {
        echo "Error: Query failed" >&2
        exit 2
    }

# Influx CSV: last data row, _value is the 4th column after header annotations
price=$(echo "$response" | awk -F, '/^,_result,/ { print $4; exit }' | tr -d ' "')

if [[ -z "$price" ]] || ! [[ "$price" =~ ^[0-9] ]]; then
    echo "Error: No price found for ${SYMBOL}" >&2
    exit 1
fi

echo "$price"
exit 0
