#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}
AVC_MODULE_NAME=${AVC_MODULE_NAME:-wifiman_desktop_local}
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

compile_and_install() {
  local module_name=$1
  local te_path=$2
  checkmodule -M -m -o "$TMP_DIR/$module_name.mod" "$te_path"
  semodule_package -o "$TMP_DIR/$module_name.pp" -m "$TMP_DIR/$module_name.mod"
  semodule -X 300 -i "$TMP_DIR/$module_name.pp"
}

cp "$BASE_TE" "$TMP_DIR/$BASE_MODULE_NAME.te"
compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te"

if command -v ausearch >/dev/null && command -v audit2allow >/dev/null; then
  if ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" >/dev/null 2>&1; then
    if ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" --raw | audit2allow -M "$AVC_MODULE_NAME" -p /var/lib/selinux/targeted/active/policy.* >/dev/null 2>&1; then
      :
    fi
    if [[ -f "$AVC_MODULE_NAME.te" ]]; then
      mv "$AVC_MODULE_NAME.te" "$TMP_DIR/$AVC_MODULE_NAME.te"
      mv "$AVC_MODULE_NAME.mod" "$TMP_DIR/$AVC_MODULE_NAME.mod"
      mv "$AVC_MODULE_NAME.pp" "$TMP_DIR/$AVC_MODULE_NAME.pp"
      semodule -X 300 -i "$TMP_DIR/$AVC_MODULE_NAME.pp"
    else
      echo "No additional AVC-derived SELinux rules were generated (since=$SINCE)."
    fi
  else
    echo "No SELinux AVC denials found for wifiman-desktop (since=$SINCE); installing base module only."
  fi
else
  echo "ausearch/audit2allow not available; installing base module only."
fi

systemctl restart wifiman-desktop.service
systemctl status wifiman-desktop.service --no-pager -l || true

echo
echo "Installed SELinux base module: $BASE_MODULE_NAME"
echo "Installed SELinux AVC module: $AVC_MODULE_NAME (if generated)"
echo "Base policy source: $BASE_TE"
echo "AVC merge window: $SINCE"
