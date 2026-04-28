#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME=${MODULE_NAME:-my-wifimandesktop}
SINCE=${SINCE:-recent}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

command -v ausearch >/dev/null
command -v audit2allow >/dev/null
command -v semodule >/dev/null

if ! ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" >/dev/null 2>&1; then
  echo "No SELinux AVC denials found for wifiman-desktop (since=$SINCE)." >&2
  echo "Start the service once first, then re-run this script if SELinux blocks it." >&2
  exit 1
fi

cd "$TMP_DIR"
ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" --raw | audit2allow -M "$MODULE_NAME"
semodule -X 300 -i "$MODULE_NAME.pp"

systemctl restart wifiman-desktop.service
systemctl status wifiman-desktop.service --no-pager -l || true

echo
echo "Installed SELinux module: $MODULE_NAME"
echo "Source window: $SINCE"
