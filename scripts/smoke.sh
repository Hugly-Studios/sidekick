#!/bin/bash
# End-to-end check: install if needed, enable a module, run a command,
# then doctor and logs. Non-zero on failure so an agent can tell.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

sidekick() {
	scripts/sidekick.sh "$@"
}

json_ok() {
	python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if data.get("ok") else 1)'
}

allow_destructive=0
if [[ "${1:-}" == "--allow-destructive" ]]; then
	allow_destructive=1
fi

if [[ ! -d /Applications/Sidekick.app ]]; then
	echo "smoke: installing Release"
	scripts/install.sh
fi

echo "smoke: waiting for the app"
ready=0
for _ in $(seq 1 20); do
	if sidekick status --json >/dev/null 2>&1; then
		ready=1
		break
	fi
	open /Applications/Sidekick.app
	sleep 1
done

if [[ "$ready" -ne 1 ]]; then
	echo "smoke: app is not answering status --json" >&2
	exit 2
fi

echo "smoke: status"
sidekick status --json | json_ok

echo "smoke: enable workspaces"
enable_json="$(sidekick features enable workspaces --json)"
echo "$enable_json" | json_ok
if echo "$enable_json" | python3 -c '
import json, sys
payload = json.load(sys.stdin).get("payload") or {}
feature = payload.get("feature") or {}
failure = feature.get("failure") or ""
if "разрешен" in failure.lower() or "permission" in failure.lower():
    print("smoke: workspaces needs a permission: " + failure, file=sys.stderr)
    sys.exit(3)
if failure:
    print("smoke: workspaces failed to activate: " + failure, file=sys.stderr)
    sys.exit(1)
'; then
	:
else
	exit $?
fi

echo "smoke: run workspaces.list"
list_json="$(sidekick run workspaces.list --json)"
if ! echo "$list_json" | json_ok; then
	if echo "$list_json" | python3 -c '
import json, sys
error = (json.load(sys.stdin).get("error") or "").lower()
sys.exit(0 if ("разрешен" in error or "permission" in error or "не найден" in error) else 1)
'; then
		echo "smoke: workspaces.list unavailable — grant Accessibility" >&2
		exit 3
	fi
	echo "smoke: workspaces.list failed" >&2
	exit 1
fi

if [[ "$allow_destructive" -eq 1 ]]; then
	echo "smoke: run workspaces.capture (destructive)"
	sidekick run workspaces.capture --arg smoke --json | json_ok
else
	echo "smoke: skipping commands that change global system state (pass --allow-destructive)"
fi

echo "smoke: doctor"
sidekick doctor --json | json_ok

echo "smoke: logs"
sidekick logs --since 5m --level error --json | json_ok

echo "smoke: ok"
