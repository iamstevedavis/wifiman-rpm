#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"

grep -q '^%{_prefix}/lib/wi-fiman-desktop/wifiman-desktop.log$' "$SPEC_FILE"
grep -q '%ghost %config(noreplace) %{_localstatedir}/lib/%{name}/wifiman-desktop.log' "$SPEC_FILE"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
BUILD_ROOT="$TMP_DIR/buildroot"
APP_ROOT="$BUILD_ROOT/usr/lib/wi-fiman-desktop"
STATE_ROOT="$BUILD_ROOT/var/lib/wifiman-desktop"
mkdir -p "$APP_ROOT"
printf 'upstream log\n' > "$APP_ROOT/wifiman-desktop.log"

# Run the spec's log installation commands rather than a copy of the logic.
sed -n '/^touch .*wifiman-desktop.log$/,/^ln .*wifiman-desktop.log$/p' "$SPEC_FILE" |
  sed -e "s|%{buildroot}|$BUILD_ROOT|g" \
      -e 's|%{_prefix}|/usr|g' \
      -e 's|%{_localstatedir}|/var|g' \
      -e 's|%{name}|wifiman-desktop|g' > "$TMP_DIR/install-log.sh"
test -s "$TMP_DIR/install-log.sh"
mkdir -p "$STATE_ROOT"

for run in 1 2; do
  bash -eu "$TMP_DIR/install-log.sh"
  test -L "$APP_ROOT/wifiman-desktop.log"
  test "$(readlink "$APP_ROOT/wifiman-desktop.log")" = '../../../var/lib/wifiman-desktop/wifiman-desktop.log'
  test "$(readlink -f "$APP_ROOT/wifiman-desktop.log")" = "$STATE_ROOT/wifiman-desktop.log"
  printf 'daemon log %s\n' "$run" >> "$APP_ROOT/wifiman-desktop.log"
done
printf 'daemon log 1\ndaemon log 2\n' > "$TMP_DIR/expected.log"
cmp "$TMP_DIR/expected.log" "$STATE_ROOT/wifiman-desktop.log"

echo "spec log symlink test passed"
