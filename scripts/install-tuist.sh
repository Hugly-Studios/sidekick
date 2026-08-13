#!/bin/bash
# Installs the Tuist version pinned in .tuist-version and prints the binary path.
# Keeps CI reproducible instead of tracking whatever Homebrew ships today.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' <"$repo_root/.tuist-version")"
install_dir="${TUIST_INSTALL_DIR:-$HOME/.cache/sidekick/tuist/$version}"
binary="$install_dir/tuist"

if [[ ! -x "$binary" ]]; then
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "$tmp_dir"' EXIT

	curl -fsSL \
		"https://github.com/tuist/tuist/releases/download/$version/tuist.zip" \
		-o "$tmp_dir/tuist.zip"

	rm -rf "$install_dir"
	mkdir -p "$install_dir"
	unzip -q "$tmp_dir/tuist.zip" -d "$install_dir"
	chmod +x "$binary"
fi

echo "$binary"
