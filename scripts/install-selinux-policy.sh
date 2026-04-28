#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODULE_NAME=${MODULE_NAME:-wifiman_desktop_local}
SINCE=${SINCE:-recent}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

command -v checkmodule >/dev/null
command -v semodule_package >/dev/null
command -v semodule >/dev/null
command -v ausearch >/dev/null || true
command -v audit2allow >/dev/null || true

BASE_TE="$SCRIPT_DIR/wifiman-desktop.te"
if [[ ! -f "$BASE_TE" ]]; then
  echo "Missing policy source: $BASE_TE" >&2
  exit 1
fi

cp "$BASE_TE" "$TMP_DIR/$MODULE_NAME.te"

if command -v ausearch >/dev/null && command -v audit2allow >/dev/null; then
  if ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" >/dev/null 2>&1; then
    ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" --raw | audit2allow -m "$MODULE_NAME" >> "$TMP_DIR/$MODULE_NAME.te" || true
  fi
fi

checkmodule -M -m -o "$TMP_DIR/$MODULE_NAME.mod" "$TMP_DIR/$MODULE_NAME.te"
semodule_package -o "$TMP_DIR/$MODULE_NAME.pp" -m "$TMP_DIR/$MODULE_NAME.mod"
semodule -X 300 -i "$TMP_DIR/$MODULE_NAME.pp"

systemctl restart wifiman-desktop.service
systemctl status wifiman-desktop.service --no-pager -l || true

echo
echo "Installed SELinux module: $MODULE_NAME"
echo "Base policy source: $BASE_TE"
echo "AVC merge window: $SINCE"
