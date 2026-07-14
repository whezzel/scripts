#!/usr/bin/env bash
# tpm2-luks-unlock.sh - Try all TPM2 tokens then fallback to passphrase

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <luks-device> <mapping-name>"
    echo "Example: $0 /dev/nvme0n1p2 mydata"
    exit 1
fi

DEVICE="$1"
MAPNAME="$2"

echo "=== Trying all TPM2 tokens for $DEVICE ==="

# Get list of systemd-tpm2 token IDs
# Format in luksDump: "  <ID>: systemd-tpm2" (type is on the header line)
TOKENS=$(sudo cryptsetup luksDump "$DEVICE" 2>/dev/null | \
         awk '/^[[:space:]]+[0-9]+:[[:space:]]*systemd-tpm2/ {
                match($0, /^[[:space:]]+([0-9]+):/, a);
                print a[1]
              }' || true)

if [ -z "$TOKENS" ]; then
    echo "No systemd-tpm2 tokens found. Falling back to passphrase."
    sudo cryptsetup open "$DEVICE" "$MAPNAME"
    exit $?
fi

echo "Found TPM2 tokens: $TOKENS"

SUCCESS=0
for TOKEN_ID in $TOKENS; do
    echo "→ Trying token $TOKEN_ID ..."

    # Redirect stdin from /dev/null so any passphrase prompt immediately gets EOF
    # --token-id forces only that specific token; failure returns immediately
    if sudo cryptsetup open --token-id "$TOKEN_ID" "$DEVICE" "$MAPNAME" < /dev/null 2>/dev/null; then
        echo "✓ Unlocked successfully with token $TOKEN_ID"
        SUCCESS=1
        break
    else
        echo "   Token $TOKEN_ID failed"
        sudo cryptsetup close "$MAPNAME" 2>/dev/null || true
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "⚠ All TPM2 tokens failed. Falling back to passphrase prompt..."
    sudo cryptsetup open "$DEVICE" "$MAPNAME"
fi
