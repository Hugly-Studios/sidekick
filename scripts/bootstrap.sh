#!/bin/bash
# Brings a clean machine to a state where `make verify` can run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

export PATH="$HOME/.local/bin:$PATH"

if ! command -v mise >/dev/null 2>&1; then
	echo "bootstrap: installing mise"
	curl -fsSL https://mise.run | sh
fi

mise trust --yes
mise install

scripts/setup-signing.sh
scripts/version.sh

mise exec -- tuist install
mise exec -- tuist generate --no-open
mise exec -- lefthook install

echo "bootstrap: ready — run make verify"
