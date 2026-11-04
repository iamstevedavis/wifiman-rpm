#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"

# Upstream wg_report.sh calls ifconfig and netstat, which Fedora ships in
# net-tools. The requirement must be unconditional, otherwise dnf can skip
# net-tools on some builds and the debug report loses interface/route data.
if ! awk '
  /^%(if|ifarch|ifnarch|ifos)([[:space:]]|$)/ { cond++ }
  /^%endif([[:space:]]|$)/ { if (cond > 0) cond-- }
  /^Requires:[[:space:]]+net-tools([[:space:]]|$)/ {
    if (cond > 0) { conditional = 1 }
    found = 1
    exit
  }
  END {
    if (conditional) { exit 1 }
    if (!found) { exit 2 }
  }
' "$SPEC_FILE"; then
  echo "Requires: net-tools must be unconditional" >&2
  exit 1
fi

# The requirement only matters while upstream's report script is packaged.
grep -q '^%{_prefix}/lib/wi-fiman-desktop/wg_report.sh$' "$SPEC_FILE"

echo "spec net-tools requirement test passed"
