#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/scripts/wifiman-teleport-diagnostics.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

BIN_DIR="$WORK_DIR/bin"
STATE_DIR="$WORK_DIR/state"
mkdir -p "$BIN_DIR" "$STATE_DIR"

test -x "$SCRIPT"
bash -n "$SCRIPT"

# --- stubbed commands ------------------------------------------------------
cat > "$BIN_DIR/wg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'wg 1.0.20210914\n' ;;
  show)
    if [[ ${2:-} == interfaces ]]; then
      printf 'wg0\n'
      exit 0
    fi
    printf '%s\n' \
      'interface: wg0' \
      '  public key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
      '  private key: SECRETKEYMATERIALAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
      '  listening port: 51820' \
      '' \
      'peer: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' \
      '  preshared key: (hidden)' \
      '  endpoint: 203.0.113.9:51820' \
      '  allowed ips: 10.64.0.2/32' \
      '  latest handshake: 12 seconds ago' \
      '  transfer: 1.23 MiB received, 456.78 KiB sent' \
      '  persistent keepalive: every 25 seconds'
    ;;
  *) exit 0 ;;
esac
EOF

cat > "$BIN_DIR/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  --version|-V)
    printf 'ip utility, iproute2-6.10.0\n'
    ;;
  *'link show type wireguard'*)
    printf '7: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1280 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\\    link/none\n'
    ;;
  *'-d link show dev wg0'*|*'link show dev wg0'*)
    printf '7: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1280 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\n    link/none  promiscuity 0\n'
    ;;
  *'-6 addr show dev wg0'*)
    printf '7: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1280\n    inet6 fd00:64::1/64 scope global\n    inet6 fe80::1/64 scope link\n'
    ;;
  *'addr show dev wg0'*)
    printf '7: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1280\n    inet 10.64.0.1/32 scope global wg0\n'
    ;;
  *'-6 route show dev wg0'*)
    printf 'fd00:64::/64 dev wg0 metric 256\n'
    ;;
  *'route show dev wg0'*)
    printf '10.64.0.2 dev wg0 scope link\n'
    ;;
  *'-6 route show'*)
    printf 'fe80::/64 dev wlan0 proto kernel metric 256\n'
    ;;
  *'route show'*)
    printf 'default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.20 metric 600\n'
    ;;
  *)
    printf '(stub ip: %s)\n' "$*"
    ;;
esac
EOF

cat > "$BIN_DIR/journalctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
kernel=0
for arg in "$@"; do
  [[ $arg == -k ]] && kernel=1
done
case " $* " in
  *' -u NetworkManager '*)
    printf 'Nov 03 21:14:00 host NetworkManager[100]: <info> device (wlan0): state change: activated -> deactivating\n'
    ;;
  *' -u wifiman-desktop.service '*)
    printf '%s\n' \
      'Nov 03 21:13:59 host wifiman-desktopd[200]: Teleport echo: Too many timeouts' \
      'Nov 03 21:14:00 host wifiman-desktopd[200]: TELEPORT_UDP_ECHO_FAILED'
    ;;
  *' -u firewalld '*)
    printf 'Nov 03 21:14:00 host firewalld[300]: DENIED inbound udp dpt=51820\n'
    ;;
  *)
    if ((kernel == 1)); then
      printf '%s\n' \
        'Nov 03 21:14:00 host kernel: filter_IN_public_REJECT: IN=wlan0 OUT= SRC=198.51.100.4 DST=192.168.1.20 LEN=76 PROTO=UDP DPT=51820' \
        'Nov 03 21:14:01 host kernel: unrelated kernel line'
    else
      printf 'journal stub\n'
    fi
    ;;
esac
EOF

cat > "$BIN_DIR/firewall-cmd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --get-log-denied) printf 'off\n' ;;
  --version) printf '2.3.0\n' ;;
  *) printf 'stub firewall-cmd\n' ;;
esac
EOF

cat > "$BIN_DIR/tcpdump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --version ]]; then
  printf 'tcpdump version 4.99.5\n'
  exit 0
fi
out=
prev=
for arg in "$@"; do
  [[ $prev == -w ]] && out=$arg
  prev=$arg
done
if [[ -n $out ]]; then
  printf 'fake pcap\n' > "$out"
  exit 0
fi
printf '%s\n' \
  '21:14:03.123456 IP 203.0.113.9.51820 > 192.168.1.20.51515: UDP, length 148' \
  '21:14:03.234567 IP6 fd00:64::2.51820 > fd00:64::1.51515: UDP, length 120'
EOF

cat > "$BIN_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -n ]] && shift
exec "$@"
EOF

chmod +x "$BIN_DIR"/*

latest_dir() {
  find "$1" -mindepth 1 -maxdepth 1 -type d -name 'teleport-*' 2>/dev/null | sort | tail -n 1
}

# --- default run: privileged collection, redaction on ----------------------
env PATH="$BIN_DIR:$PATH" XDG_STATE_HOME="$STATE_DIR" \
  bash "$SCRIPT" --interface wg0 --capture-seconds 1 --capture-count 5 \
  > "$WORK_DIR/run.out" 2>&1

OUT_DIR=$(latest_dir "$STATE_DIR/wifiman-desktop/teleport-diagnostics")
test -n "$OUT_DIR"
test -d "$OUT_DIR"
[[ $(basename "$OUT_DIR") =~ ^teleport-[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
[[ $(stat -c %a "$OUT_DIR") == 700 ]]
grep -q "Wrote diagnostics to $OUT_DIR" "$WORK_DIR/run.out"

for file in README.txt system.txt wg-show.txt interfaces.txt routes.txt \
  networkmanager-journal.txt wifiman-journal.txt firewalld-denied.txt tcpdump-wg.txt; do
  test -s "$OUT_DIR/$file"
done

# Interface name, MTU and IPv6 addresses are the #28/#21 evidence.
grep -q '^interface: wg0$' "$OUT_DIR/interfaces.txt"
grep -q '^mtu: 1280$' "$OUT_DIR/interfaces.txt"
grep -q 'inet6 fd00:64::1/64' "$OUT_DIR/interfaces.txt"
grep -q '10.64.0.1/32' "$OUT_DIR/interfaces.txt"
grep -q '10.64.0.2 dev wg0' "$OUT_DIR/routes.txt"
grep -q 'fd00:64::/64 dev wg0' "$OUT_DIR/routes.txt"
grep -q 'default via 192.168.1.1 dev wlan0' "$OUT_DIR/routes.txt"

# Redaction: keys and endpoint details are gone, useful evidence stays.
grep -q 'transfer: 1.23 MiB received' "$OUT_DIR/wg-show.txt"
grep -q 'latest handshake: 12 seconds ago' "$OUT_DIR/wg-show.txt"
grep -qi 'private key.*\[REDACTED\]' "$OUT_DIR/wg-show.txt"
grep -q 'endpoint: \[REDACTED\]' "$OUT_DIR/wg-show.txt"
if grep -q 'SECRETKEYMATERIAL' "$OUT_DIR/wg-show.txt"; then
  echo 'private key material leaked into wg-show.txt' >&2
  exit 1
fi
if grep -q '203.0.113.9' "$OUT_DIR/wg-show.txt"; then
  echo 'WireGuard endpoint leaked into wg-show.txt' >&2
  exit 1
fi

# Journal evidence.
grep -q 'NetworkManager\[100\]' "$OUT_DIR/networkmanager-journal.txt"
grep -q 'TELEPORT_UDP_ECHO_FAILED' "$OUT_DIR/wifiman-journal.txt"
grep -q 'filter_IN_public_REJECT' "$OUT_DIR/firewalld-denied.txt"
grep -q '^off$' "$OUT_DIR/firewalld-denied.txt"
grep -qi 'does not log dropped packets' "$OUT_DIR/firewalld-denied.txt"

# Bounded capture is text and address-redacted.
grep -q 'length 148' "$OUT_DIR/tcpdump-wg.txt"
grep -q '\[REDACTED\]' "$OUT_DIR/tcpdump-wg.txt"
if grep -q '203.0.113.9\|192.168.1.20\|fd00:64::2' "$OUT_DIR/tcpdump-wg.txt"; then
  echo 'tcpdump addresses were not redacted' >&2
  exit 1
fi
test ! -e "$OUT_DIR/wg.pcap"

# The bundle explains itself and what was collected.
grep -q 'Redaction (default output):' "$OUT_DIR/README.txt"
grep -q 'wg-show.txt (wg show, redacted)' "$OUT_DIR/README.txt"
grep -q 'tcpdump-wg.txt (bounded capture, addresses redacted)' "$OUT_DIR/README.txt"
grep -q 'read-only' "$OUT_DIR/README.txt"

# --- --pcap is opt-in and clearly marked as unredacted ---------------------
PCAP_STATE="$WORK_DIR/state-pcap"
env PATH="$BIN_DIR:$PATH" XDG_STATE_HOME="$PCAP_STATE" \
  bash "$SCRIPT" -i wg0 --pcap --capture-seconds 1 --capture-count 5 \
  > "$WORK_DIR/pcap.out" 2>&1
PCAP_DIR=$(latest_dir "$PCAP_STATE/wifiman-desktop/teleport-diagnostics")
test -s "$PCAP_DIR/wg.pcap"
grep -q 'NOT redacted' "$WORK_DIR/pcap.out"
grep -q 'RAW capture, NOT redacted' "$PCAP_DIR/README.txt"
grep -q 'Raw .pcap output (--pcap) is NOT redacted' "$PCAP_DIR/README.txt"

# --- --no-capture leaves capture out but still records why -----------------
NO_CAPTURE_STATE="$WORK_DIR/state-no-capture"
env PATH="$BIN_DIR:$PATH" XDG_STATE_HOME="$NO_CAPTURE_STATE" \
  bash "$SCRIPT" -i wg0 --no-capture > "$WORK_DIR/no-capture.out" 2>&1
NO_CAPTURE_DIR=$(latest_dir "$NO_CAPTURE_STATE/wifiman-desktop/teleport-diagnostics")
test ! -e "$NO_CAPTURE_DIR/tcpdump-wg.txt"
grep -q 'disabled by --no-capture' "$NO_CAPTURE_DIR/README.txt"

# --- missing tools degrade gracefully -------------------------------------
MIN_BIN="$WORK_DIR/min-bin"
mkdir -p "$MIN_BIN"
for tool in bash date mkdir chmod sed uname hostname grep cat mv rm basename; do
  ln -s "$(command -v "$tool")" "$MIN_BIN/$tool"
done

env -i PATH="$MIN_BIN" HOME="$WORK_DIR/home" XDG_STATE_HOME="$WORK_DIR/state-min" \
  bash "$SCRIPT" > "$WORK_DIR/min.out" 2>&1
MIN_DIR=$(latest_dir "$WORK_DIR/state-min/wifiman-desktop/teleport-diagnostics")
test -n "$MIN_DIR"
test -s "$MIN_DIR/README.txt"
test -s "$MIN_DIR/system.txt"
test ! -e "$MIN_DIR/wg-show.txt"
test ! -e "$MIN_DIR/interfaces.txt"
test ! -e "$MIN_DIR/routes.txt"
test ! -e "$MIN_DIR/tcpdump-wg.txt"
grep -q 'wg-show.txt (wg not installed)' "$MIN_DIR/README.txt"
grep -q 'interfaces.txt (ip not installed)' "$MIN_DIR/README.txt"
grep -q 'tcpdump capture (tcpdump not installed)' "$MIN_DIR/README.txt"
grep -q 'networkmanager-journal.txt (journalctl or grep not installed)' "$MIN_DIR/README.txt"

# --- no interface / no privileges is reported, not fatal ------------------
env PATH="$BIN_DIR:$PATH" XDG_STATE_HOME="$WORK_DIR/state-no-sudo" \
  WIFIMAN_DIAG_ALLOW_SUDO=0 bash "$SCRIPT" --interface wgx0 --no-capture \
  > "$WORK_DIR/no-sudo.out" 2>&1
NO_SUDO_DIR=$(latest_dir "$WORK_DIR/state-no-sudo/wifiman-desktop/teleport-diagnostics")
grep -q 'Interface:  wgx0' "$NO_SUDO_DIR/README.txt"

# --- help does not create output ------------------------------------------
env XDG_STATE_HOME="$WORK_DIR/state-help" bash "$SCRIPT" --help > "$WORK_DIR/help.out"
grep -q '^Usage:' "$WORK_DIR/help.out"
test ! -e "$WORK_DIR/state-help"

echo "Teleport diagnostics test passed"
