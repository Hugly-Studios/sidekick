#!/bin/bash
# Removes the installed copy. With --purge also drops settings, caches,
# leftover copies and permission grants.
set -euo pipefail

app_name="Sidekick"
bundle_id="com.hugly.sidekick"
destination="/Applications/$app_name.app"
support="$HOME/Library/Application Support/$bundle_id"
caches="$HOME/Library/Caches/$bundle_id"
http_storages="$HOME/Library/HTTPStorages/$bundle_id"
saved_state="$HOME/Library/Saved Application State/$bundle_id.savedState"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$scripts_dir/sidekick.sh" quit >/dev/null 2>&1 || true
osascript -e "quit app \"$app_name\"" >/dev/null 2>&1 || true
sleep 1
pkill -x "$app_name" >/dev/null 2>&1 || true

uid="$(id -u)"
launchctl bootout "gui/$uid/$bundle_id.login" >/dev/null 2>&1 || true

if [[ -d "$destination" ]]; then
	rm -rf "$destination"
	echo "removed $destination"
else
	echo "nothing installed at $destination"
fi

if [[ "${1:-}" != "--purge" ]]; then
	exit 0
fi

copies="$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null || true)"
while IFS= read -r copy; do
	[[ -z "$copy" ]] && continue
	echo "removing leftover copy: $copy"
	rm -rf "$copy"
done <<<"$copies"

defaults delete "$bundle_id" >/dev/null 2>&1 || true
rm -rf "$support" "$caches" "$http_storages" "$saved_state"
tccutil reset All "$bundle_id" >/dev/null 2>&1 || true

echo "purged settings, caches, leftover copies and permission grants for $bundle_id"
