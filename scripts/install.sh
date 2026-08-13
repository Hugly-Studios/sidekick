#!/bin/bash
# Builds a Release copy and installs it to /Applications.
#
# Always the same destination path and the same signing team, so repeated
# installs keep granted permissions and the login item registration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_name="Sidekick"
destination="/Applications/$app_name.app"
built_app="build/Build/Products/Release/$app_name.app"

scripts/tuist.sh generate --no-open >/dev/null

xcodebuild \
	-workspace "$app_name.xcworkspace" \
	-scheme "$app_name" \
	-configuration Release \
	-destination 'platform=macOS' \
	-derivedDataPath build \
	-quiet \
	build

codesign --verify --strict "$built_app"

# Quit both the installed copy and any dev build so the replacement is clean.
osascript -e "quit app \"$app_name\"" >/dev/null 2>&1 || true
pkill -x "$app_name" >/dev/null 2>&1 || true
sleep 1

rm -rf "$destination"
cp -R "$built_app" "$destination"
xattr -dr com.apple.quarantine "$destination" 2>/dev/null || true

version="$(defaults read "$destination/Contents/Info.plist" CFBundleShortVersionString)"
build_number="$(defaults read "$destination/Contents/Info.plist" CFBundleVersion)"
team="$(codesign -dv "$destination" 2>&1 | sed -n 's/^TeamIdentifier=//p')"

echo "installed $app_name $version ($build_number) to $destination"
echo "signing team: ${team:-none}"

open "$destination"
