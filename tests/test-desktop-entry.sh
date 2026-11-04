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
grep -qx 'MimeType=x-scheme-handler/wifiman-desktop-dl;' "$DESKTOP_FILE"
grep -qx 'Categories=Network;' "$DESKTOP_FILE"

# A key may appear only once per group. desktop-file-validate rejects duplicates
# and fails the RPM %check, so catch them here without needing the tool.
dupes=$(grep -E '^[A-Za-z-]+(\[[^]]+\])?=' "$DESKTOP_FILE" | cut -d= -f1 | sort | uniq -d)
if [[ -n "$dupes" ]]; then
  echo "duplicate desktop entry keys: $dupes" >&2
  exit 1
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE"
fi

# The window's app id / WM_CLASS comes from the executable name the launcher
# runs. Without a matching StartupWMClass the taskbar shows a generic icon.
grep -qx 'StartupWMClass=wi-fiman-desktop-bin' "$DESKTOP_FILE"
grep -qx 'UI_BINARY_NAME=wi-fiman-desktop-bin' "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
grep -qx 'DEEP_LINK_HANDLER_NAME="$UI_BINARY_NAME-handler.desktop"' "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
grep -qx 'RUNTIME_EXTRA_ITEMS=("$UI_BINARY_NAME")' "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
grep -qx 'exec "$RUNTIME_ROOT/$UI_BINARY_NAME" "$@"' "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
grep -q "StartupWMClass=wi-fiman-desktop-bin' %{buildroot}" "$SPEC_FILE"

grep -q 'Source5:        wifiman-desktop.desktop' "$SPEC_FILE"
grep -q 'install -m 0644 %{SOURCE5}' "$SPEC_FILE"
grep -q 'desktop-file-validate %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop' "$SPEC_FILE"
grep -q "grep -qx 'MimeType=x-scheme-handler/wifiman-desktop-dl;' %{buildroot}%{_datadir}/applications/wifiman-desktop.desktop" "$SPEC_FILE"
grep -qx 'Requires:       xdg-utils' "$SPEC_FILE"
grep -q 'wifiman-desktop.desktop' "$BUILD_SCRIPT"

echo 'desktop entry test passed'
