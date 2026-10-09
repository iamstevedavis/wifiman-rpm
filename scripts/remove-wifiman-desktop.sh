#!/usr/bin/env bash
set -euo pipefail

APP_NAME=${APP_NAME:-wifiman-desktop}
SERVICE_NAME=${SERVICE_NAME:-wifiman-desktop.service}
USER_STATE_ROOT=${USER_STATE_ROOT:-"${XDG_STATE_HOME:-$HOME/.local/state}/wifiman-desktop"}
REMOVE_USER_STATE=${REMOVE_USER_STATE:-1}
REMOVE_SYSTEM_STATE=${REMOVE_SYSTEM_STATE:-1}
REMOVE_SELINUX_MODULES=${REMOVE_SELINUX_MODULES:-0}
DNF_CLEAN_METADATA=${DNF_CLEAN_METADATA:-1}
BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}
AVC_MODULE_NAME=${AVC_MODULE_NAME:-wifiman_desktop_local}
SELINUX_MODULE_PRIORITY=${SELINUX_MODULE_PRIORITY:-300}

run_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

log() {
  printf '==> %s\n' "$*"
}

selinux_module_present() {
  run_sudo semodule -lfull 2>/dev/null |
    awk -v prio="$SELINUX_MODULE_PRIORITY" -v name="$1" \
      '$1 == prio && $2 == name { found = 1 } END { exit found ? 0 : 1 }'
}

remove_selinux_module() {
  local module_name=$1
  if ! selinux_module_present "$module_name"; then
    log "SELinux module $module_name not present at priority $SELINUX_MODULE_PRIORITY; skipping"
    return 0
  fi
  log "Removing SELinux module $module_name at priority $SELINUX_MODULE_PRIORITY"
  run_sudo semodule -X "$SELINUX_MODULE_PRIORITY" -r "$module_name"
}

log "Stopping and disabling $SERVICE_NAME if present"
run_sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

log "Removing RPM package $APP_NAME if installed"
if rpm -q "$APP_NAME" >/dev/null 2>&1; then
  run_sudo dnf remove -y "$APP_NAME"
else
  log "$APP_NAME is not installed"
fi

if [[ "$DNF_CLEAN_METADATA" == "1" ]]; then
  log "Cleaning DNF metadata cache"
  run_sudo dnf clean metadata
fi

if [[ "$REMOVE_SYSTEM_STATE" == "1" ]]; then
  log "Removing system runtime state: /var/lib/$APP_NAME"
  run_sudo rm -rf "/var/lib/$APP_NAME"
else
  log "Keeping system runtime state because REMOVE_SYSTEM_STATE=$REMOVE_SYSTEM_STATE"
fi

if [[ "$REMOVE_USER_STATE" == "1" ]]; then
  log "Removing user runtime state: $USER_STATE_ROOT"
  rm -rf "$USER_STATE_ROOT"
else
  log "Keeping user runtime state because REMOVE_USER_STATE=$REMOVE_USER_STATE"
fi

if [[ "$REMOVE_SELINUX_MODULES" == "1" ]]; then
  log "Removing local SELinux modules installed at priority $SELINUX_MODULE_PRIORITY"
  remove_selinux_module "$BASE_MODULE_NAME"
  remove_selinux_module "$AVC_MODULE_NAME"
else
  log "Keeping SELinux modules. Set REMOVE_SELINUX_MODULES=1 to remove them."
fi

log "Cleaning stale desktop/icon caches where available"
run_sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
run_sudo gtk-update-icon-cache /usr/share/icons/hicolor >/dev/null 2>&1 || true

log "Post-removal checks"
rpm -qa | grep -i wifiman || true
systemctl status "$SERVICE_NAME" --no-pager -l || true

log "Removal/cleanup complete"
