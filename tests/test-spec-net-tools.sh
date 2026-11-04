#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"

# Upstream wg_report.sh calls ifconfig and netstat, which Fedora ships in
# net-tools. Keep the dependency declared now that the script is packaged.
grep -Eq '^Requires:[[:space:]]+net-tools([[:space:]]|$)' "$SPEC_FILE"
grep -q '^%{_prefix}/lib/wi-fiman-desktop/wg_report.sh$' "$SPEC_FILE"

echo "spec net-tools requirement test passed"
