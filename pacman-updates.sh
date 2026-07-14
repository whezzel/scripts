#!/usr/bin/env bash

set -euo pipefail

pkglist() {
	if command -v yay >/dev/null 2>&1; then
		pkg_list=$(yay -Quq 2>/dev/null || true)
	else
		pkg_list=$(pacman -Quq 2>/dev/null || true)
	fi
	if [[ -n "${pkg_list:-}" ]]; then
		pkg_list=$(printf '%s\n' "$pkg_list" | sort)
	fi
}

pkgcount() {
	if [[ -n "${pkg_list:-}" ]]; then
		printf '%s\n' "$(printf '%s\n' "$pkg_list" | wc -l)"
	else
		printf '0\n'
	fi
}

list() {
	if [[ -z "${pkg_list:-}" ]]; then
		return
	fi
	# Soft-wrap long package lists for status bars
	printf '%s\n' "$pkg_list" | tr '\n' ' ' | sed -e 's/.\{71\}/&\n/g'
	echo
}

pkglist
pkgcount
list
