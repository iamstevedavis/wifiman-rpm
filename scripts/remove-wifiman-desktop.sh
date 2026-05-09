#!/usr/bin/env bash
set -euo pipefail

APP_NAME=${APP_NAME:-wifiman-desktop}
SERVICE_NAME=${SERVICE_NAME:-wifiman-desktop.service}
USER_STATE_ROOT=${USER_STATE_ROOT:-"${XDG_STATE_HOME:-$HOME/.local/state}/wifiman-desktop"}
REMOVE_USER_STATE=${REMOVE_USER_STATE:-1}
REMOVE_SYSTEM_STATE=${REMOVE_SYSTEM_STATE:-1}
REMOVE_SELINUX_MODULES=${REMOVE_SELINUX_MODULES:-0}

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

log "Stopping and disabling $SERVICE_NAME if present"
run_sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

log "Removing RPM package $APP_NAME if installed"
if rpm -q "$APP_NAME" >/dev/null 2>&1; then
  run_sudo dnf remove -y "$APP_NAME"
else
  log "$APP_NAME is not installed"
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
  log "Removing local SELinux modules if installed"
  run_sudo semodule -r wifiman-desktop 2>/dev/null || true
  run_sudo semodule -r wifiman-desktop-local 2>/dev/null || true
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
