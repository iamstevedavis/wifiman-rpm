#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DESKTOP_FILE="$ROOT_DIR/scripts/wifiman-desktop.desktop"
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-rpm-from-stage.sh"

bash -n "$BUILD_SCRIPT"
test -f "$DESKTOP_FILE"

grep -qx 'Name=WiFiman Desktop' "$DESKTOP_FILE"
grep -qx 'Exec=wifiman-desktop %U' "$DESKTOP_FILE"
grep -qx 'Icon=wifiman-desktop' "$DESKTOP_FILE"
grep -qx 'Categories=Network;' "$DESKTOP_FILE"

grep -q 'Source5:        wifiman-desktop.desktop' "$SPEC_FILE"
grep -q 'install -m 0644 %{SOURCE5}' "$SPEC_FILE"
grep -q 'desktop-file-validate %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop' "$SPEC_FILE"
grep -q 'wifiman-desktop.desktop' "$BUILD_SCRIPT"

echo 'desktop entry test passed'
