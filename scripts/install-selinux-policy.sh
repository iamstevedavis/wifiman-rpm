#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME=${MODULE_NAME:-my-wifimandesktop}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

command -v ausearch >/dev/null
command -v audit2allow >/dev/null
command -v semodule >/dev/null

cd "$TMP_DIR"
ausearch -c 'wifiman-desktop' --raw | audit2allow -M "$MODULE_NAME"
semodule -X 300 -i "$MODULE_NAME.pp"

echo "Installed SELinux module: $MODULE_NAME"
echo "You can now restart the daemon with: systemctl restart wifiman-desktop.service"
