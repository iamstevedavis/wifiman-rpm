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
  echo "===== SERVICE COUNTERS ====="
  systemctl show "$SERVICE_NAME" \
    -p NRestarts -p ExecMainStartTimestamp -p Environment 2>/dev/null || true

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
  echo "===== WIREGUARD ====="
  if command -v wg >/dev/null 2>&1; then
    run_sudo wg show all 2>/dev/null || true
    echo "--- latest handshakes ---"
    run_sudo wg show all latest-handshakes 2>/dev/null || true
    echo "--- transfer ---"
    run_sudo wg show all transfer 2>/dev/null || true
    # Never run "wg show ... dump" or "wg showconf" here: both print each
    # interface's private key, and this log is meant to be shared.
  else
    echo "wg not installed"
  fi
  echo "--- addresses ---"
  ip -brief address 2>/dev/null || true
  echo "--- routes ---"
  ip route show table all 2>/dev/null || true
  ip -6 route show table all 2>/dev/null || true
  echo "--- rules ---"
  ip rule show 2>/dev/null || true
  ip -6 rule show 2>/dev/null || true
  echo "--- links ---"
  ip link show 2>/dev/null || true
  echo "--- sysctls ---"
  sysctl net.ipv4.conf.all.src_valid_mark 2>/dev/null || true
  sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null || true
  echo "--- resolvconf ---"
  command -v resolvconf 2>/dev/null || true
  systemctl is-active systemd-resolved 2>/dev/null || true

  echo
  echo "===== FIREWALL ====="
  if command -v firewall-cmd >/dev/null 2>&1; then
    run_sudo firewall-cmd --state 2>/dev/null || true
    run_sudo firewall-cmd --get-default-zone 2>/dev/null || true
    run_sudo firewall-cmd --get-active-zones 2>/dev/null || true
    run_sudo firewall-cmd --get-log-denied 2>/dev/null || true
    run_sudo firewall-cmd --list-all-zones 2>/dev/null || true
  else
    echo "firewall-cmd not installed"
  fi
  if command -v nft >/dev/null 2>&1; then
    echo "--- nft list ruleset (first 400 lines) ---"
    run_sudo nft list ruleset 2>/dev/null | head -n 400 || true
  fi
  if command -v iptables-save >/dev/null 2>&1; then
    echo "--- iptables-save (first 200 lines) ---"
    run_sudo iptables-save 2>/dev/null | head -n 200 || true
  fi
  if command -v ip6tables-save >/dev/null 2>&1; then
    echo "--- ip6tables-save (first 200 lines) ---"
    run_sudo ip6tables-save 2>/dev/null | head -n 200 || true
  fi

  echo
  echo "===== INSTALLED FILES ====="
  ls -la /usr/bin/wifiman-desktop /usr/lib/wi-fiman-desktop 2>/dev/null || true

  echo
  echo "===== SELINUX ====="
  getenforce 2>/dev/null || true
  run_sudo semodule -l 2>/dev/null | grep -i wifiman || true
  run_sudo ausearch -m AVC -ts recent 2>/dev/null |
    grep -Ei 'wifiman|wg-quick|wireguard|sysctl_net_t|net_conf_t|nft|iptables' -A5 -B2 || true

  echo
  echo "===== PROCESS ====="
  ps auxww | grep -i '[w]ifiman\|[w]i-fiman' || true
} 2>&1 | tee "$OUT"

echo
echo "Wrote debug log to: $OUT"
