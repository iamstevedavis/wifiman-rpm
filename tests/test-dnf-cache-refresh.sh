#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-and-run-wifiman-desktop.sh"
REMOVE_SCRIPT="$ROOT_DIR/scripts/remove-wifiman-desktop.sh"
README="$ROOT_DIR/README.md"

bash -n "$INSTALL_SCRIPT"
bash -n "$REMOVE_SCRIPT"

grep -q 'DNF_CLEAN_METADATA=${DNF_CLEAN_METADATA:-1}' "$INSTALL_SCRIPT"
grep -q 'DNF_CLEAN_METADATA=${DNF_CLEAN_METADATA:-1}' "$REMOVE_SCRIPT"
grep -q 'run_sudo dnf clean metadata' "$INSTALL_SCRIPT"
grep -q 'run_sudo dnf clean metadata' "$REMOVE_SCRIPT"
grep -q 'run_sudo dnf --refresh install -y "$@"' "$INSTALL_SCRIPT"
grep -q 'DNF_CLEAN_METADATA=0 ./scripts/install-and-run-wifiman-desktop.sh' "$README"

echo 'dnf cache refresh test passed'
