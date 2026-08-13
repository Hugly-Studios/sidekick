#!/bin/bash
# Removes the installed copy. With --purge also drops settings and permissions,
# which is what you want before testing a first-run experience.
set -euo pipefail

app_name="Sidekick"
bundle_id="com.hugly.sidekick"
destination="/Applications/$app_name.app"

osascript -e "quit app \"$app_name\"" >/dev/null 2>&1 || true
pkill -x "$app_name" >/dev/null 2>&1 || true

if [[ -d "$destination" ]]; then
	rm -rf "$destination"
	echo "removed $destination"
else
	echo "nothing installed at $destination"
fi

if [[ "${1:-}" == "--purge" ]]; then
	defaults delete "$bundle_id" >/dev/null 2>&1 || true
	tccutil reset All "$bundle_id" >/dev/null 2>&1 || true
	echo "purged settings and permission grants for $bundle_id"
	echo "the login item entry disappears once macOS notices the app is gone"
fi
