#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME=${APP_NAME:-wifiman-desktop}
SERVICE_NAME=${SERVICE_NAME:-wifiman-desktop.service}
RPM_GLOB=${RPM_GLOB:-"$ROOT_DIR/.rpmbuild/RPMS/x86_64/wifiman-desktop-*.rpm"}
RPM_PATH=${RPM_PATH:-}
BUILD_RPM=${BUILD_RPM:-1}
START_SERVICE=${START_SERVICE:-1}
LAUNCH_APP=${LAUNCH_APP:-0}
INSTALL_BUILD_DEPS=${INSTALL_BUILD_DEPS:-1}
INSTALL_SELINUX_POLICY=${INSTALL_SELINUX_POLICY:-0}
DNF_REFRESH=${DNF_REFRESH:-1}
DNF_CLEAN_METADATA=${DNF_CLEAN_METADATA:-1}

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

dnf_install() {
  if [[ "$DNF_REFRESH" == "1" ]]; then
    run_sudo dnf --refresh install -y "$@"
  else
    run_sudo dnf install -y "$@"
  fi
}

if [[ "$DNF_CLEAN_METADATA" == "1" ]]; then
  log "Cleaning DNF metadata cache"
  run_sudo dnf clean metadata
fi

if [[ "$INSTALL_BUILD_DEPS" == "1" ]]; then
  log "Installing build/runtime helper packages"
  dnf_install docker git policycoreutils-python-utils setools-console
  log "Enabling Docker"
  run_sudo systemctl enable --now docker
fi

if [[ "$BUILD_RPM" == "1" ]]; then
  log "Building RPM"
  "$ROOT_DIR/scripts/build-rpm-from-stage.sh"
fi

if [[ -z "$RPM_PATH" ]]; then
  shopt -s nullglob
  rpm_candidates=( $RPM_GLOB )
  shopt -u nullglob
  if [[ ${#rpm_candidates[@]} -eq 0 ]]; then
    echo "No RPM found matching: $RPM_GLOB" >&2
    echo "Build one first or set RPM_PATH=/path/to/wifiman-desktop.rpm" >&2
    exit 1
  fi
  IFS=$'\n' read -r -d '' -a sorted_rpms < <(printf '%s\n' "${rpm_candidates[@]}" | sort -V && printf '\0')
  RPM_PATH=${sorted_rpms[-1]}
fi

log "Installing RPM: $RPM_PATH"
dnf_install "$RPM_PATH"

if [[ "$INSTALL_SELINUX_POLICY" == "1" ]]; then
  log "Installing bundled SELinux policy helper"
  "$ROOT_DIR/scripts/install-selinux-policy.sh"
fi

if [[ "$START_SERVICE" == "1" ]]; then
  log "Enabling and starting $SERVICE_NAME"
  run_sudo systemctl enable --now "$SERVICE_NAME"
  run_sudo systemctl status "$SERVICE_NAME" --no-pager -l || true
fi

if [[ "$LAUNCH_APP" == "1" ]]; then
  log "Launching desktop app"
  wifiman-desktop "$@"
else
  log "Desktop app is installed. Launch it with: wifiman-desktop"
  log "Or run this script with LAUNCH_APP=1 to launch after install."
fi

log "Install/run complete"
