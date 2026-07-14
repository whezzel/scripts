#!/usr/bin/env bash

set -euo pipefail

HOST="${WAIT_TUNNEL_HOST:-nas01.whezzel.com}"
TIMEOUT_SEC="${WAIT_TUNNEL_TIMEOUT:-180}"
PING_WAIT="${WAIT_TUNNEL_PING_WAIT:-5}"
SLEEP_SEC="${WAIT_TUNNEL_SLEEP:-4}"

echo "[$(date '+%F %T')] === Waiting for WireGuard tunnel to ${HOST} (max ${TIMEOUT_SEC}s) ==="

if ! timeout "$TIMEOUT_SEC" bash -c "
  until ping -c 1 -W ${PING_WAIT} '${HOST}' >/dev/null 2>&1; do
    sleep ${SLEEP_SEC}
  done
"; then
  echo "[$(date '+%F %T')] ERROR: Tunnel to ${HOST} did not come up in time!" >&2
  exit 1
fi

echo "[$(date '+%F %T')] WireGuard tunnel is ready!"
