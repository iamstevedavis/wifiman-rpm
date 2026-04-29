#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"

grep -q 'ln -sfn %{_localstatedir}/lib/%{name}/wifiman-desktop.log %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log' "$SPEC_FILE"
grep -q '%ghost %{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log' "$SPEC_FILE"
grep -q '%ghost %config(noreplace) %{_localstatedir}/lib/%{name}/wifiman-desktop.log' "$SPEC_FILE"

echo "spec log symlink test passed"
