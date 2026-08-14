#!/bin/bash
# Builds a Release copy and installs it to /Applications.
#
# Always the same destination path and the same signing team, so repeated
# installs keep granted permissions and the login item registration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

export PATH="$HOME/.local/bin:$PATH"

app_name="Sidekick"
bundle_id="com.hugly.sidekick"
destination="/Applications/$app_name.app"
built_app="build/Build/Products/Release/$app_name.app"

team_of() {
	codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1
}

scripts/version.sh
mise exec -- tuist generate --no-open >/dev/null

xcodebuild \
	-workspace "$app_name.xcworkspace" \
	-scheme "$app_name" \
	-configuration Release \
	-destination 'platform=macOS' \
	-derivedDataPath build \
	-quiet \
	build

codesign --verify --strict "$built_app"

new_team="$(team_of "$built_app")"
if [[ -d "$destination" ]]; then
	old_team="$(team_of "$destination")"
	if [[ "${old_team:-none}" != "${new_team:-none}" ]]; then
		echo "warning: Team ID changes from ${old_team:-none} to ${new_team:-none}"
		echo "warning: macOS will drop granted permissions after this install"
	fi
fi

# Prefer a graceful quit so a Debug copy is not killed by pkill.
scripts/sidekick.sh quit >/dev/null 2>&1 || true
osascript -e "quit app \"$app_name\"" >/dev/null 2>&1 || true
sleep 1
if pgrep -x "$app_name" >/dev/null 2>&1; then
	pkill -x "$app_name" >/dev/null 2>&1 || true
	sleep 1
fi

copies="$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null || true)"
while IFS= read -r copy; do
	[[ -z "$copy" ]] && continue
	case "$copy" in
	"$destination" | "$repo_root/build/"*)
		continue
		;;
	*"DerivedData"*)
		echo "note: leftover copy in DerivedData (not removed): $copy"
		;;
	*)
		echo "removing extra copy: $copy"
		rm -rf "$copy"
		;;
	esac
done <<<"$copies"

rm -rf "$destination"
cp -R "$built_app" "$destination"
xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true

version="$(defaults read "$destination/Contents/Info.plist" CFBundleShortVersionString)"
build_number="$(defaults read "$destination/Contents/Info.plist" CFBundleVersion)"

echo "installed $app_name $version ($build_number) to $destination"
echo "signing team: ${new_team:-none}"

open "$destination"

# `status` needs a live control socket, so it cannot succeed before the app is
# up. `doctor` would: it falls back to an offline report and exits zero.
ready=0
for _ in $(seq 1 30); do
	if scripts/sidekick.sh status --json >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 1
done

if [[ "$ready" -ne 1 ]]; then
	echo "install failed: app did not answer status --json" >&2
	exit 1
fi

echo "install ok — app answers status"
