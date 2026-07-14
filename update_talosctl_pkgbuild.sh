#!/usr/bin/env bash

set -euo pipefail

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required (install with 'sudo pacman -S jq')" >&2; exit 1; }
command -v updpkgsums >/dev/null 2>&1 || { echo "updpkgsums is required (install with 'sudo pacman -S devtools')" >&2; exit 1; }

if [[ ! -f PKGBUILD ]]; then
  echo "Error: PKGBUILD not found in $(pwd)" >&2
  exit 1
fi

# Get latest stable release tag from GitHub API
api_response=$(curl -fsSL https://api.github.com/repos/siderolabs/talos/releases/latest)
tag=$(echo "$api_response" | jq -r .tag_name)

if [[ -z "$tag" || "$tag" == "null" ]]; then
  echo "Failed to fetch latest tag" >&2
  echo "$api_response" >&2
  exit 1
fi

# Extract pkgver (remove leading 'v')
pkgver=${tag#v}

# Update PKGBUILD pkgver
sed -i "s/^pkgver=.*/pkgver=$pkgver/" PKGBUILD

# Update checksums using updpkgsums
updpkgsums || { echo "Failed to update checksums" >&2; exit 1; }

# Clean up downloaded file (assuming filename from source)
rm -f talosctl-linux-amd64

echo "PKGBUILD updated to version $pkgver"
