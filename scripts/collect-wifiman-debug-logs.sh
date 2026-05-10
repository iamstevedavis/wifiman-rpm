#!/usr/bin/env bash
set -euo pipefail

APP_NAME=${APP_NAME:-wifiman-desktop}
SERVICE_NAME=${SERVICE_NAME:-wifiman-desktop.service}
OUT=${OUT:-/tmp/wifiman-debug.log}
JOURNAL_LINES=${JOURNAL_LINES:-300}
APP_LOG_LINES=${APP_LOG_LINES:-300}

run_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

{
  echo "===== DATE ====="
  date -Is

  echo
  echo "===== OS ====="
  cat /etc/fedora-release 2>/dev/null || cat /etc/os-release 2>/dev/null || true

  echo
  echo "===== KERNEL ====="
  uname -a

  echo
  echo "===== RPM ====="
  rpm -qa | grep -i wifiman || true
  rpm -qi "$APP_NAME" 2>/dev/null || true
  rpm -ql "$APP_NAME" 2>/dev/null || true

  echo
  echo "===== SERVICE STATUS ====="
  systemctl status "$SERVICE_NAME" --no-pager -l || true

  echo
  echo "===== JOURNAL ====="
  journalctl -u "$SERVICE_NAME" -b --no-pager -n "$JOURNAL_LINES" || true

  echo
  echo "===== APP LOG ====="
  run_sudo tail -n "$APP_LOG_LINES" "/var/lib/$APP_NAME/wifiman-desktop.log" 2>/dev/null || true

  echo
  echo "===== RUNTIME STATE ====="
  run_sudo ls -la "/var/lib/$APP_NAME" 2>/dev/null || true
  ls -la "${XDG_STATE_HOME:-$HOME/.local/state}/wifiman-desktop" 2>/dev/null || true

  echo
  echo "===== INSTALLED FILES ====="
  ls -la /usr/bin/wifiman-desktop /usr/lib/wi-fiman-desktop 2>/dev/null || true

  echo
  echo "===== SELINUX ====="
  getenforce 2>/dev/null || true
  run_sudo semodule -l 2>/dev/null | grep -i wifiman || true
  run_sudo ausearch -m AVC -ts recent 2>/dev/null | grep -i wifiman -A5 -B2 || true

  echo
  echo "===== PROCESS ====="
  ps auxww | grep -i '[w]ifiman\|[w]i-fiman' || true
} 2>&1 | tee "$OUT"

echo
echo "Wrote debug log to: $OUT"
