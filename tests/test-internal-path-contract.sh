#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Wrapper defaults, installed service and file ownership must share one root.
for wrapper in wifiman-desktop-launcher.sh wifiman-desktopd-wrapper.sh; do
  grep -Fxq 'APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}' "$ROOT_DIR/scripts/$wrapper"
done
for item in wi-fiman-desktop-bin wifiman-desktopd-wrapper wifiman-runtime.sh; do
  grep -Fxq "%{_prefix}/lib/wi-fiman-desktop/$item" "$SPEC_FILE"
done
grep -Fxq '%dir %{_prefix}/lib/wi-fiman-desktop' "$SPEC_FILE"
grep -Fxq 'Exec=wifiman-desktop %U' "$ROOT_DIR/scripts/wifiman-desktop.desktop"

for spelling in wi-fiman-desktop wifiman-desktop; do
  CASE_ROOT="$TMP_DIR/$spelling"
  BUILD_ROOT="$CASE_ROOT/buildroot"
  mkdir -p "$CASE_ROOT/staged/upstream/usr/bin" \
    "$CASE_ROOT/staged/upstream/usr/lib/$spelling"
  printf 'mock UI payload\n' > "$CASE_ROOT/staged/upstream/usr/bin/$spelling"
  printf 'mock daemon payload\n' > "$CASE_ROOT/staged/upstream/usr/lib/$spelling/wifiman-desktopd"
  printf '[Service]\nExecStart=/usr/lib/%s/wifiman-desktopd\n' "$spelling" > \
    "$CASE_ROOT/staged/upstream/usr/lib/$spelling/wifiman-desktop.service"

  # Execute the actual spec selection and installation blocks, not duplicated
  # packaging logic. Icon selection and compatibility libraries are unrelated.
  {
    sed -n '/^UPSTREAM_BIN=$/,/^UPSTREAM_ICON_32=$/p' "$SPEC_FILE" | sed '$d'
    sed -n '/^install -d %{buildroot}%{_prefix}\/lib\/wi-fiman-desktop$/,/^install -d %{buildroot}%{_localstatedir}/p' "$SPEC_FILE" | sed '$d'
    sed -n '/^install -d %{buildroot}%{_bindir}$/,/^install -d %{buildroot}%{_datadir}\/applications$/p' "$SPEC_FILE" | sed '$d'
  } | sed -e "s|%{buildroot}|$BUILD_ROOT|g" \
    -e 's|%{_prefix}|/usr|g' \
    -e 's|%{_bindir}|/usr/bin|g' \
    -e 's|%{_unitdir}|/usr/lib/systemd/system|g' \
    -e 's|%{name}|wifiman-desktop|g' \
    -e "s|%{SOURCE2}|$ROOT_DIR/scripts/wifiman-desktop-launcher.sh|g" \
    -e "s|%{SOURCE4}|$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh|g" \
    -e "s|%{SOURCE6}|$ROOT_DIR/scripts/wifiman-runtime.sh|g" > "$CASE_ROOT/install.sh"
  (cd "$CASE_ROOT" && bash -eu install.sh)

  APP_ROOT="$BUILD_ROOT/usr/lib/wi-fiman-desktop"
  cmp "$CASE_ROOT/staged/upstream/usr/bin/$spelling" "$APP_ROOT/wi-fiman-desktop-bin"
  cmp "$CASE_ROOT/staged/upstream/usr/lib/$spelling/wifiman-desktopd" "$APP_ROOT/wifiman-desktopd"
  cmp "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh" "$BUILD_ROOT/usr/bin/wifiman-desktop"
  cmp "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh" "$APP_ROOT/wifiman-desktopd-wrapper"
  cmp "$ROOT_DIR/scripts/wifiman-runtime.sh" "$APP_ROOT/wifiman-runtime.sh"
  test -x "$APP_ROOT/wi-fiman-desktop-bin"
  test -x "$APP_ROOT/wifiman-desktopd-wrapper"
  test ! -e "$BUILD_ROOT/usr/lib/wifiman-desktop"
  grep -Fxq 'ExecStart=/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper' \
    "$BUILD_ROOT/usr/lib/systemd/system/wifiman-desktop.service"
done

echo "internal path contract test passed"
