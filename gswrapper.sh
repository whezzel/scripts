#!/usr/bin/env bash

set -euo pipefail

gsout="/tmp/gswrapper.gamescope.out"
gamescope_opts=(-w 3440 -h 1440 -r 165 -f --hdr-enabled --adaptive-sync)
command_args=()

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    command_args=("$@")
    break
  fi
  gamescope_opts+=("$1")
  shift
done

if (( ${#command_args[@]} == 0 )); then
  echo "Usage: $0 [gamescope options] -- <command> [args...]" >&2
  exit 1
fi

: > "$gsout"
echo "gamescope opts: ${gamescope_opts[*]}" >> "$gsout"

gamescope "${gamescope_opts[@]}" &>>"$gsout" &
gs_pid=$!

cleanup() {
  if kill -0 "$gs_pid" 2>/dev/null; then
    kill "$gs_pid" 2>/dev/null || true
    wait "$gs_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

display=""
deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  if [[ -f "$gsout" ]]; then
    display=$(sed -nE 's/^.*Starting Xwayland on :([0-9]+).*$/\1/p' "$gsout" | head -n1)
    [[ -n "$display" ]] && break
  fi
  # Bail early if gamescope died
  if ! kill -0 "$gs_pid" 2>/dev/null; then
    echo "gamescope exited before Xwayland started. Log:" >&2
    cat "$gsout" >&2
    exit 1
  fi
  sleep 0.1
done

if [[ -z "$display" ]]; then
  echo "Timed out waiting for Xwayland (30s). Log:" >&2
  cat "$gsout" >&2
  exit 1
fi

DISPLAY=":$display" "${command_args[@]}"
