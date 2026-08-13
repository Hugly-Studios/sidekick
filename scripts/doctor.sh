#!/bin/bash
# Runs Sidekick's own diagnostics, preferring the installed copy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="Sidekick"

for candidate in \
	"/Applications/$app_name.app" \
	"$repo_root/build/Build/Products/Release/$app_name.app" \
	"$repo_root/build/Build/Products/Debug/$app_name.app"; do
	if [[ -d "$candidate" ]]; then
		exec "$candidate/Contents/MacOS/$app_name" --doctor
	fi
done

echo "no built app found — run: make build"
exit 1
