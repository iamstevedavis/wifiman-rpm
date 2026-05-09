#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

scripts=(
  "$ROOT_DIR/scripts/remove-wifiman-desktop.sh"
  "$ROOT_DIR/scripts/install-and-run-wifiman-desktop.sh"
  "$ROOT_DIR/scripts/collect-wifiman-debug-logs.sh"
)

for script in "${scripts[@]}"; do
  bash -n "$script"
  test -x "$script"
done
