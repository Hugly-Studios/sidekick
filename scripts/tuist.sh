#!/bin/bash
# Runs the pinned Tuist.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$("$script_dir/install-tuist.sh")" "$@"
