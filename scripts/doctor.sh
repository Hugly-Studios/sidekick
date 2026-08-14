#!/bin/bash
# Runs Sidekick's own diagnostics, preferring the installed copy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$repo_root/scripts/sidekick.sh" doctor --json
