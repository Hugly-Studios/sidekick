#!/bin/bash
# Formats a just-written Swift file. Cursor sends JSON on stdin.
set -euo pipefail

payload="$(cat)"
path="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("file_path") or json.loads(sys.argv[1]).get("path") or "")' "$payload")"

if [[ "$path" == *.swift && -f "$path" ]]; then
	xcrun swift-format format --in-place "$path"
fi

echo '{}'
