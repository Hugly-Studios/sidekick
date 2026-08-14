#!/bin/bash
# Formats Swift files the agent just wrote. Fail-open: a missing tool must
# not block the edit.
set -euo pipefail

input="$(cat)"
file="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("file") or json.loads("""'"$input"'""") if False else "")' 2>/dev/null || true)"

if [[ -z "$file" ]]; then
	file="$(printf '%s' "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("file") or d.get("path") or "")')"
fi

if [[ "$file" != *.swift ]]; then
	echo '{}'
	exit 0
fi

if [[ ! -f "$file" ]]; then
	echo '{}'
	exit 0
fi

xcrun swift-format format --in-place "$file" >/dev/null 2>&1 || true
echo '{}'
