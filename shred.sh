#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <file>" >&2
    exit 1
fi

if [[ ! -e $1 ]]; then
    echo "Error: '$1' does not exist" >&2
    exit 1
fi

if [[ ! -f $1 ]]; then
    echo "Error: '$1' is not a regular file" >&2
    exit 1
fi

printf "Writing Random\n"
shred -n1 "$1"
printf "Syncing Filesystem\n"
sync
shred -v -n 0 -z -u "$1"
