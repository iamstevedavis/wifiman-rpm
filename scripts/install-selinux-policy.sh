#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}
AVC_MODULE_NAME=${AVC_MODULE_NAME:-wifiman_desktop_local}
SELINUX_MODULE_PRIORITY=${SELINUX_MODULE_PRIORITY:-300}
SINCE=${SINCE:-recent}
REVIEWED_AVC_TE=${REVIEWED_AVC_TE:-}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ "${WIFIMAN_ASSUME_ROOT_FOR_TESTS:-0}" != "1" && ${EUID:-$(id -u)} -ne 0 ]]; then
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

# Snapshot an explicitly reviewed source before changing installed policy.
if [[ -n "$REVIEWED_AVC_TE" ]]; then
  if [[ ! -f "$REVIEWED_AVC_TE" || ! -s "$REVIEWED_AVC_TE" ]]; then
    echo "Missing or empty reviewed policy source: $REVIEWED_AVC_TE" >&2
    exit 1
  fi
  cp "$REVIEWED_AVC_TE" "$TMP_DIR/$AVC_MODULE_NAME.te"
fi

echo "WARNING: the base policy still grants permissions to shared init_t and generic file labels." >&2
echo "It is not confined to WiFiman; see docs/selinux-validation.md and issue #15." >&2

compile_and_install() {
  local module_name=$1
  local te_path=$2
  checkmodule -M -m -o "$TMP_DIR/$module_name.mod" "$te_path"
  semodule_package -o "$TMP_DIR/$module_name.pp" -m "$TMP_DIR/$module_name.mod"
  semodule -X "$SELINUX_MODULE_PRIORITY" -i "$TMP_DIR/$module_name.pp"
}

cp "$BASE_TE" "$TMP_DIR/$BASE_MODULE_NAME.te"
compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te"

if [[ -n "$REVIEWED_AVC_TE" ]]; then
  echo "Installing explicitly reviewed AVC policy source: $REVIEWED_AVC_TE"
  cat "$TMP_DIR/$AVC_MODULE_NAME.te"
  compile_and_install "$AVC_MODULE_NAME" "$TMP_DIR/$AVC_MODULE_NAME.te"
elif command -v ausearch >/dev/null && command -v audit2allow >/dev/null; then
  if ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" >/dev/null 2>&1; then
    ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" --raw > "$TMP_DIR/avc.log"
    audit2allow -m "$AVC_MODULE_NAME" -p /var/lib/selinux/targeted/active/policy.* < "$TMP_DIR/avc.log" > "$TMP_DIR/$AVC_MODULE_NAME.te"
    REVIEW_DIR=$(mktemp -d /var/tmp/wifiman-selinux-review.XXXXXX)
    cp "$TMP_DIR/avc.log" "$TMP_DIR/$AVC_MODULE_NAME.te" "$REVIEW_DIR/"
    echo "AVC policy draft (NOT installed): $REVIEW_DIR/$AVC_MODULE_NAME.te"
    echo "Audit evidence: $REVIEW_DIR/avc.log"
    echo "Review every rule and its source/target labels; comm filtering does not scope SELinux permissions."
    echo "After review, pass the source path using REVIEWED_AVC_TE (see README.md)."
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
if [[ -n "$REVIEWED_AVC_TE" ]]; then
  echo "Installed SELinux AVC module: $AVC_MODULE_NAME (explicitly reviewed source)"
else
  echo "No AVC-derived module installed; existing local modules are unchanged."
fi
echo "SELinux module priority: $SELINUX_MODULE_PRIORITY"
echo "Base policy source: $BASE_TE"
echo "AVC review window: $SINCE"
