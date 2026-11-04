#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}
AVC_MODULE_NAME=${AVC_MODULE_NAME:-wifiman_desktop_local}
SELINUX_MODULE_PRIORITY=${SELINUX_MODULE_PRIORITY:-300}
SINCE=${SINCE:-recent}
REVIEWED_AVC_TE=${REVIEWED_AVC_TE:-}
# The dedicated domain is the default. The legacy policy remains available
# explicitly and is the automatic fallback if the transition fails.
# See docs/selinux-validation.md.
POLICY_VARIANT=${WIFIMAN_SELINUX_POLICY:-dedicated}
APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}
STATE_ROOT=${STATE_ROOT:-/var/lib/wifiman-desktop}
SERVICE_NAME=${SERVICE_NAME:-wifiman-desktop.service}
DOMAIN=wifiman_t
DEDICATED_TE="$SCRIPT_DIR/wifiman-desktop.te"
DEDICATED_FC="$SCRIPT_DIR/wifiman-desktop.fc"
LEGACY_TE="$SCRIPT_DIR/wifiman-desktop-legacy.te"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

case "$POLICY_VARIANT" in
  legacy)
    BASE_TE=$LEGACY_TE
    ;;
  dedicated)
    BASE_TE=$DEDICATED_TE
    ;;
  *)
    echo "Unknown WIFIMAN_SELINUX_POLICY '$POLICY_VARIANT' (use legacy or dedicated)" >&2
    exit 1
    ;;
esac

if [[ "${WIFIMAN_ASSUME_ROOT_FOR_TESTS:-0}" != "1" && ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

command -v checkmodule >/dev/null
command -v semodule_package >/dev/null
command -v semodule >/dev/null
command -v ausearch >/dev/null || true
command -v audit2allow >/dev/null || true

if [[ ! -f "$BASE_TE" ]]; then
  echo "Missing policy source: $BASE_TE" >&2
  exit 1
fi
if [[ "$POLICY_VARIANT" == "dedicated" && ! -f "$DEDICATED_FC" ]]; then
  echo "Missing file-context source: $DEDICATED_FC" >&2
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

if [[ "$POLICY_VARIANT" == "legacy" ]]; then
  echo "WARNING: the legacy base policy grants permissions to shared init_t and generic file labels." >&2
  echo "It is not confined to WiFiman; use WIFIMAN_SELINUX_POLICY=dedicated for the scoped policy." >&2
  echo "See docs/selinux-validation.md and issue #15." >&2
else
  echo "Installing the dedicated WiFiman daemon policy (domain $DOMAIN)." >&2
  echo "The desktop UI stays in the user's domain; see docs/selinux-validation.md." >&2
fi

compile_and_install() {
  local module_name=$1
  local te_path=$2
  local fc_path=${3:-}
  checkmodule -M -m -o "$TMP_DIR/$module_name.mod" "$te_path"
  if [[ -n "$fc_path" ]]; then
    semodule_package -o "$TMP_DIR/$module_name.pp" -m "$TMP_DIR/$module_name.mod" -f "$fc_path"
  else
    semodule_package -o "$TMP_DIR/$module_name.pp" -m "$TMP_DIR/$module_name.mod"
  fi
  semodule -X "$SELINUX_MODULE_PRIORITY" -i "$TMP_DIR/$module_name.pp"
}

restore_default_labels() {
  command -v restorecon >/dev/null || return 0
  if [[ -d "$APP_ROOT" ]]; then
    restorecon -R "$APP_ROOT"
  fi
  if [[ -d "$STATE_ROOT" ]]; then
    # The legacy policy relies on the packaged runtime copies keeping lib_t
    # from the package tree. The wrapper recreates them on restart.
    restorecon -R "$STATE_ROOT"
  fi
}

relabel_dedicated() {
  command -v restorecon >/dev/null

  # Label the packaged tree from the module's file contexts.
  if [[ -d "$APP_ROOT" ]]; then
    restorecon -R "$APP_ROOT"
  fi

  # Relabel the whole runtime mirror before the first dedicated start. The
  # wrapper removes and recreates every mirrored item except service.json, so
  # old legacy labels (lib_t/var_lib_t) cannot block its rm -rf, and copied
  # executables are recreated with wifiman_helper_exec_t afterwards.
  if [[ -d "$STATE_ROOT" ]]; then
    restorecon -R "$STATE_ROOT"
  fi
}

stop_service() {
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
}

restart_service() {
  systemctl restart "$SERVICE_NAME" || return 1
  systemctl status "$SERVICE_NAME" --no-pager -l || true
}

verify_dedicated_domain() {
  local pid domain attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || true)
    if [[ -n "${pid:-}" && "$pid" != "0" ]]; then
      domain=$(ps -o label= -p "$pid" 2>/dev/null || true)
      if [[ -z "$domain" && -r "/proc/$pid/attr/current" ]]; then
        { read -r domain < "/proc/$pid/attr/current"; } 2>/dev/null || true
      fi
      if [[ "$domain" == *":$DOMAIN:"* ]]; then
        echo "Verified $SERVICE_NAME main PID $pid runs as $DOMAIN"
        return 0
      fi
    fi
    sleep 0.5
  done
  echo "wifiman-desktop did not enter $DOMAIN (last label: ${domain:-unknown})" >&2
  return 1
}

revert_to_legacy() {
  echo "Restoring the legacy policy so the daemon is not left unconfined or broken." >&2
  stop_service
  if ! compile_and_install "$BASE_MODULE_NAME" "$LEGACY_TE"; then
    echo "ERROR: failed to compile or install the legacy policy." >&2
    echo "The dedicated module may still be installed and the service is stopped." >&2
    echo "Recovery: rerun with WIFIMAN_SELINUX_POLICY=legacy, or install the legacy .pp manually." >&2
    return 1
  fi
  if ! restore_default_labels; then
    echo "WARNING: legacy module installed, but restoring default file labels failed." >&2
  fi
  if ! restart_service; then
    echo "WARNING: legacy module installed, but the service restart failed." >&2
  fi
  echo "Legacy policy restored. Review the denials above and retry with WIFIMAN_SELINUX_POLICY=dedicated." >&2
}

cp "$BASE_TE" "$TMP_DIR/$BASE_MODULE_NAME.te"

# Stop before replacing a module when switching away from dedicated. If the
# daemon is currently wifiman_t, removing that type would leave systemd unable
# to signal the process.
if [[ "$POLICY_VARIANT" == "legacy" ]]; then
  stop_service
fi

if [[ "$POLICY_VARIANT" == "dedicated" ]]; then
  compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te" "$DEDICATED_FC"
else
  compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te"
fi

# Install explicitly reviewed policy before the first restart so it can
# address a startup denial instead of triggering the fallback path.
if [[ -n "$REVIEWED_AVC_TE" ]]; then
  echo "Installing explicitly reviewed AVC policy source: $REVIEWED_AVC_TE"
  cat "$TMP_DIR/$AVC_MODULE_NAME.te"
  compile_and_install "$AVC_MODULE_NAME" "$TMP_DIR/$AVC_MODULE_NAME.te"
fi

if [[ "$POLICY_VARIANT" == "dedicated" ]]; then
  stop_service
  if ! relabel_dedicated || ! restart_service || ! verify_dedicated_domain; then
    revert_to_legacy || true
    exit 1
  fi
else
  restore_default_labels
  restart_service
fi

if [[ -z "$REVIEWED_AVC_TE" ]]; then
  if command -v ausearch >/dev/null && command -v audit2allow >/dev/null; then
    if ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" >/dev/null 2>&1; then
      ausearch -m AVC -c 'wifiman-desktop' -ts "$SINCE" --raw > "$TMP_DIR/avc.log"
      audit2allow -m "$AVC_MODULE_NAME" -p /var/lib/selinux/targeted/active/policy.* < "$TMP_DIR/avc.log" > "$TMP_DIR/$AVC_MODULE_NAME.te"
      REVIEW_DIR=$(mktemp -d /var/tmp/wifiman-selinux-review.XXXXXX)
      cp "$TMP_DIR/avc.log" "$TMP_DIR/$AVC_MODULE_NAME.te" "$REVIEW_DIR/"
      echo "AVC policy draft (NOT installed): $REVIEW_DIR/$AVC_MODULE_NAME.te"
      echo "Audit evidence: $REVIEW_DIR/avc.log"
      echo "Review every rule and its source/target labels; comm filtering does not scope SELinux permissions."
      if [[ "$POLICY_VARIANT" == "dedicated" ]]; then
        echo "Dedicated mode expects the source domain to be $DOMAIN; reject init_t rules."
      fi
      echo "After review, pass the source path using REVIEWED_AVC_TE (see README.md)."
    else
      echo "No SELinux AVC denials found for wifiman-desktop (since=$SINCE); installing base module only."
    fi
  else
    echo "ausearch/audit2allow not available; installing base module only."
  fi
fi

echo
echo "Installed SELinux base module: $BASE_MODULE_NAME (variant: $POLICY_VARIANT)"
if [[ -n "$REVIEWED_AVC_TE" ]]; then
  echo "Installed SELinux AVC module: $AVC_MODULE_NAME (explicitly reviewed source)"
else
  echo "No AVC-derived module installed; existing local modules are unchanged."
fi
echo "SELinux module priority: $SELINUX_MODULE_PRIORITY"
echo "Base policy source: $BASE_TE"
echo "AVC review window: $SINCE"
if [[ "$POLICY_VARIANT" == "dedicated" ]]; then
  echo "Daemon domain: $DOMAIN"
  echo "Packaged data label: wifiman_lib_t"
  echo "Packaged helper label: wifiman_helper_exec_t"
  echo "Runtime helper label: wifiman_runtime_exec_t"
  echo "Daemon state/runtime data label: wifiman_var_t"
fi
