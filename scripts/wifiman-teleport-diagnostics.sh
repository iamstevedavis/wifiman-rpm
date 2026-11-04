#!/usr/bin/env bash
# Read-only Teleport / WireGuard diagnostics collector for issue #29.
#
# Captures a single snapshot of the evidence needed to tell an MTU / path
# problem apart from a WireGuard handshake or firewall problem:
#
#   - wg show (keys and endpoint lines redacted)
#   - WireGuard interface name, MTU, IPv4/IPv6 addresses and routes
#   - bounded tcpdump capture of UDP traffic on the tunnel interface
#   - recent NetworkManager and wifiman-desktop journal lines
#   - firewalld denied-packet lines and the current LogDenied setting
#
# It never changes network, firewall, service or SELinux state. Every step
# degrades gracefully when a tool is missing or privileges are unavailable.
#
# Usage: wifiman-teleport-diagnostics.sh [options]
#   -i, --interface IFACE     WireGuard interface (default: auto-detect)
#       --lines N             journal lines per unit (default: 400)
#       --capture-seconds N   tcpdump time limit (default: 30)
#       --capture-count N     tcpdump packet limit (default: 200)
#       --no-capture          skip tcpdump entirely
#       --pcap                keep a raw .pcap instead of redacted text
#                             (NOT redacted: contains outer addresses)
#       --no-sudo             never invoke sudo
#   -h, --help                show this help
#
# Environment:
#   XDG_STATE_HOME            output parent (default: ~/.local/state)
#   DIAG_ROOT                 explicit output parent directory
#   WG_INTERFACE              default interface
#   JOURNAL_LINES, KERNEL_LINES, CAPTURE_COUNT, CAPTURE_SECONDS
#   WIFIMAN_DIAG_ALLOW_SUDO   set to 0 to never invoke sudo
set -uo pipefail
umask 077

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")
JOURNAL_LINES=${JOURNAL_LINES:-400}
KERNEL_LINES=${KERNEL_LINES:-4000}
CAPTURE_COUNT=${CAPTURE_COUNT:-200}
CAPTURE_SECONDS=${CAPTURE_SECONDS:-30}
ALLOW_SUDO=${WIFIMAN_DIAG_ALLOW_SUDO:-1}

WANT_CAPTURE=1
WANT_PCAP=0
SELECTED_IFACE=${WG_INTERFACE:-}

usage() {
  printf '%s\n' \
    "Usage: $SCRIPT_NAME [options]" \
    '' \
    'Read-only Teleport/WireGuard diagnostics for issue #29.' \
    '' \
    'Options:' \
    '  -i, --interface IFACE     WireGuard interface (default: auto-detect)' \
    '      --lines N             journal lines per unit (default: 400)' \
    '      --capture-seconds N   tcpdump time limit (default: 30)' \
    '      --capture-count N     tcpdump packet limit (default: 200)' \
    '      --no-capture          skip tcpdump entirely' \
    '      --pcap                keep a raw .pcap instead of redacted text' \
    '                            (NOT redacted: contains outer addresses)' \
    '      --no-sudo             never invoke sudo' \
    '  -h, --help                show this help' \
    '' \
    'Output: a timestamped directory under ${XDG_STATE_HOME:-~/.local/state}' \
    'or /tmp. WireGuard private/preshared keys and endpoint lines are' \
    'redacted by default.'
}

is_number() {
  [[ ${1:-} =~ ^[0-9]+$ ]]
}

while (($#)); do
  case "$1" in
    -i|--interface)
      if (($# < 2)); then
        printf '%s: %s needs an argument\n' "$SCRIPT_NAME" "$1" >&2
        exit 2
      fi
      SELECTED_IFACE=$2
      shift 2
      ;;
    --lines)
      if (($# < 2)) || ! is_number "${2:-}"; then
        printf '%s: --lines needs a number\n' "$SCRIPT_NAME" >&2
        exit 2
      fi
      JOURNAL_LINES=$2
      shift 2
      ;;
    --capture-seconds)
      if (($# < 2)) || ! is_number "${2:-}"; then
        printf '%s: --capture-seconds needs a number\n' "$SCRIPT_NAME" >&2
        exit 2
      fi
      CAPTURE_SECONDS=$2
      shift 2
      ;;
    --capture-count)
      if (($# < 2)) || ! is_number "${2:-}"; then
        printf '%s: --capture-count needs a number\n' "$SCRIPT_NAME" >&2
        exit 2
      fi
      CAPTURE_COUNT=$2
      shift 2
      ;;
    --no-capture)
      WANT_CAPTURE=0
      shift
      ;;
    --pcap)
      WANT_PCAP=1
      shift
      ;;
    --no-sudo)
      ALLOW_SUDO=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '%s: unknown option: %s\n' "$SCRIPT_NAME" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

have() {
  command -v "$1" >/dev/null 2>&1
}

# sed is what keeps private keys out of the bundle; refuse to run without it.
if ! have sed; then
  printf '%s: sed is required for output redaction\n' "$SCRIPT_NAME" >&2
  exit 1
fi
if ! have date; then
  printf '%s: date is required to name the output directory\n' "$SCRIPT_NAME" >&2
  exit 1
fi

IS_ROOT=0
if [[ ${EUID:-1} -eq 0 ]]; then
  IS_ROOT=1
fi

SUDO_OK=0
if ((IS_ROOT == 0)) && [[ $ALLOW_SUDO == 1 ]] && have sudo && sudo -n true >/dev/null 2>&1; then
  SUDO_OK=1
fi

# Run a read-only command with the best privilege we have, without prompting.
priv() {
  if ((IS_ROOT == 1)); then
    "$@"
  elif ((SUDO_OK == 1)); then
    sudo -n "$@"
  else
    "$@"
  fi
}

timestamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null) || timestamp=$(date +%Y%m%dT%H%M%S)
DIR_NAME="teleport-${timestamp}-$$"

bases=()
if [[ -n ${DIAG_ROOT:-} ]]; then
  bases=("$DIAG_ROOT")
elif [[ -n ${XDG_STATE_HOME:-} ]]; then
  bases=("$XDG_STATE_HOME/wifiman-desktop/teleport-diagnostics" "/tmp/wifiman-teleport-diagnostics")
elif ((IS_ROOT == 1)); then
  bases=("/tmp/wifiman-teleport-diagnostics")
else
  bases=("${HOME:-/tmp}/.local/state/wifiman-desktop/teleport-diagnostics" "/tmp/wifiman-teleport-diagnostics")
fi

OUT_DIR=
for base in "${bases[@]}"; do
  if mkdir -p "$base/$DIR_NAME" 2>/dev/null; then
    OUT_DIR="$base/$DIR_NAME"
    break
  fi
done

if [[ -z $OUT_DIR ]]; then
  printf '%s: could not create an output directory under: %s\n' "$SCRIPT_NAME" "${bases[*]}" >&2
  exit 1
fi
if have chmod; then
  chmod 700 "$OUT_DIR" 2>/dev/null || true
fi

OK_LIST=()
SKIP_LIST=()
CURRENT_FILE=

record_ok() { OK_LIST+=("$1"); }
record_skip() { SKIP_LIST+=("$1"); }

new_file() {
  CURRENT_FILE="$OUT_DIR/$1"
  {
    printf '# %s\n' "$2"
    printf '# collected: %s\n' "$(date -Is 2>/dev/null || date -u 2>/dev/null || printf unknown)"
    printf '\n'
  } > "$CURRENT_FILE"
}

run_into() {
  "$@" >> "$CURRENT_FILE" 2>&1 </dev/null \
    || printf '(command failed: %s)\n' "$*" >> "$CURRENT_FILE"
}

redact_file() {
  local file=$1 tmp="$1.redact.$$"
  if ! sed -E \
      -e 's/^([[:space:]]*(private key|preshared key)[[:space:]]*:).*/\1 [REDACTED]/I' \
      -e 's/^([[:space:]]*PrivateKey[[:space:]]*=).*/\1 [REDACTED]/I' \
      -e 's/^([[:space:]]*PresharedKey[[:space:]]*=).*/\1 [REDACTED]/I' \
      -e 's/^([[:space:]]*endpoint:).*/\1 [REDACTED]/I' \
      -e 's|[A-Za-z0-9+/]{43}=|[REDACTED-KEY]|g' \
      -e 's/(IP6? )[0-9A-Fa-f.:]+ > [0-9A-Fa-f.:]+:/\1[REDACTED]/' \
      "$file" > "$tmp" 2>/dev/null; then
    if have rm; then rm -f "$tmp"; fi
    printf '# WARNING: redaction failed; contents withheld\n' > "$file"
    return 1
  fi
  if have mv; then
    mv "$tmp" "$file"
  else
    printf '%s: mv is required for redaction\n' "$SCRIPT_NAME" >&2
    exit 1
  fi
}

# Discover the tunnel interface without assuming it is up.
detect_interface() {
  if [[ -n $SELECTED_IFACE ]]; then
    IFACE=$SELECTED_IFACE
    return 0
  fi
  local list line dev _ rest
  IFACE=
  if have wg; then
    list=$(wg show interfaces 2>/dev/null) || list=
    if [[ -n $list ]]; then
      read -r IFACE _ <<< "$list"
    fi
  fi
  if [[ -z $IFACE ]] && have ip; then
    while IFS= read -r line; do
      read -r _ dev _ <<< "$line"
      dev=${dev%:}
      if [[ -n $dev ]]; then
        IFACE=$dev
        break
      fi
    done < <(ip -o link show type wireguard 2>/dev/null)
  fi
  return 0
}

detect_interface
IFACE=${IFACE:-}

MTU=
if [[ -n $IFACE ]] && have ip; then
  MTU=$(priv ip -o link show dev "$IFACE" 2>/dev/null | sed -n 's/.* mtu \([0-9][0-9]*\).*/\1/p' | sed -n '1p')
fi

# --- system summary -------------------------------------------------------
if have uname || have hostname; then
  new_file system.txt 'Host, kernel, tool versions and WireGuard link list'
  if have uname; then run_into uname -a; fi
  if have hostname; then
    printf 'hostname: %s\n' "$(hostname 2>/dev/null || printf unknown)" >> "$CURRENT_FILE"
  fi
  if [[ -r /etc/os-release ]]; then
    printf '\n-- /etc/os-release --\n' >> "$CURRENT_FILE"
    run_into sed -n 's/^\(PRETTY_NAME\|VERSION_ID\)=/\1=/p' /etc/os-release
  fi
  for tool in wg ip tcpdump firewall-cmd journalctl; do
    if have "$tool"; then
      printf '\n-- %s version --\n' "$tool" >> "$CURRENT_FILE"
      case "$tool" in
        wg) run_into wg --version ;;
        ip) run_into ip -V ;;
        tcpdump) run_into tcpdump --version ;;
        firewall-cmd) run_into firewall-cmd --version ;;
        journalctl) run_into journalctl --version ;;
      esac
    fi
  done
  if have ip; then
    printf '\n-- ip -o link show type wireguard --\n' >> "$CURRENT_FILE"
    run_into priv ip -o link show type wireguard
  fi
  redact_file "$CURRENT_FILE"
  record_ok "system.txt (host, kernel, tool versions, wg links)"
else
  record_skip "system.txt (uname and hostname unavailable)"
fi

# --- wg show --------------------------------------------------------------
if have wg; then
  new_file wg-show.txt 'wg show output (private keys and endpoints redacted)'
  if [[ -n $IFACE ]]; then
    run_into priv wg show "$IFACE"
  else
    printf '(no WireGuard interface detected; showing all)\n' >> "$CURRENT_FILE"
    run_into priv wg show
  fi
  if redact_file "$CURRENT_FILE"; then
    record_ok "wg-show.txt (wg show, redacted)"
  else
    record_skip "wg-show.txt (redaction failed; withheld)"
  fi
else
  record_skip "wg-show.txt (wg not installed)"
fi

# --- interface name, MTU, addresses --------------------------------------
if have ip && [[ -n $IFACE ]]; then
  new_file interfaces.txt "WireGuard interface $IFACE: MTU, IPv4 and IPv6 addresses"
  printf 'interface: %s\n' "$IFACE" >> "$CURRENT_FILE"
  printf 'mtu: %s\n\n' "${MTU:-unknown}" >> "$CURRENT_FILE"
  run_into priv ip -d link show dev "$IFACE"
  printf '\n-- ip addr show dev %s --\n' "$IFACE" >> "$CURRENT_FILE"
  run_into priv ip addr show dev "$IFACE"
  printf '\n-- ip -6 addr show dev %s --\n' "$IFACE" >> "$CURRENT_FILE"
  run_into priv ip -6 addr show dev "$IFACE"
  redact_file "$CURRENT_FILE"
  record_ok "interfaces.txt ($IFACE, mtu ${MTU:-unknown})"
elif ! have ip; then
  record_skip "interfaces.txt (ip not installed)"
else
  record_skip "interfaces.txt (no WireGuard interface detected; is Teleport connected?)"
fi

# --- routes ---------------------------------------------------------------
if have ip; then
  new_file routes.txt 'IPv4/IPv6 routes, including per-interface routes'
  if [[ -n $IFACE ]]; then
    printf '\n-- ip route show dev %s --\n' "$IFACE" >> "$CURRENT_FILE"
    run_into priv ip route show dev "$IFACE"
    printf '\n-- ip -6 route show dev %s --\n' "$IFACE" >> "$CURRENT_FILE"
    run_into priv ip -6 route show dev "$IFACE"
  fi
  printf '\n-- ip route show --\n' >> "$CURRENT_FILE"
  run_into priv ip route show
  printf '\n-- ip -6 route show --\n' >> "$CURRENT_FILE"
  run_into priv ip -6 route show
  redact_file "$CURRENT_FILE"
  record_ok "routes.txt (IPv4/IPv6 routes)"
else
  record_skip "routes.txt (ip not installed)"
fi

# --- NetworkManager journal ----------------------------------------------
if have journalctl && have grep; then
  new_file networkmanager-journal.txt 'Recent NetworkManager journal lines (current boot)'
  if ! priv journalctl -u NetworkManager -u NetworkManager-dispatcher -b --no-pager \
      -n "$JOURNAL_LINES" >> "$CURRENT_FILE" 2>&1 </dev/null; then
    printf '(journalctl could not read the system journal; try running with sudo)\n' >> "$CURRENT_FILE"
    record_skip "networkmanager-journal.txt (journal not readable without privileges)"
  else
    record_ok "networkmanager-journal.txt (NetworkManager journal)"
  fi
  redact_file "$CURRENT_FILE"
else
  record_skip "networkmanager-journal.txt (journalctl or grep not installed)"
fi

# --- wifiman-desktop journal ---------------------------------------------
if have journalctl; then
  new_file wifiman-journal.txt 'Recent wifiman-desktop.service journal lines (current boot)'
  if ! priv journalctl -u wifiman-desktop.service -b --no-pager \
      -n "$JOURNAL_LINES" >> "$CURRENT_FILE" 2>&1 </dev/null; then
    printf '(journalctl could not read the system journal; try running with sudo)\n' >> "$CURRENT_FILE"
    record_skip "wifiman-journal.txt (journal not readable without privileges)"
  else
    record_ok "wifiman-journal.txt (wifiman-desktop service journal)"
  fi
  redact_file "$CURRENT_FILE"
else
  record_skip "wifiman-journal.txt (journalctl not installed)"
fi

# --- firewalld denied packets --------------------------------------------
if have journalctl && have grep; then
  new_file firewalld-denied.txt 'firewalld denied/dropped packet lines and LogDenied setting'
  if have firewall-cmd; then
    printf '== firewall-cmd --get-log-denied ==\n' >> "$CURRENT_FILE"
    if log_denied=$(firewall-cmd --get-log-denied 2>/dev/null); then
      printf '%s\n' "${log_denied:-unknown}" >> "$CURRENT_FILE"
      case "$log_denied" in
        off|'')
          printf '(LogDenied is off: firewalld does not log dropped packets, so missing lines here prove nothing.)\n' \
            >> "$CURRENT_FILE"
          ;;
      esac
    else
      printf '(firewall-cmd --get-log-denied failed; firewalld may be inactive)\n' >> "$CURRENT_FILE"
    fi
  else
    printf '(firewall-cmd not installed)\n' >> "$CURRENT_FILE"
  fi
  printf '\n== kernel: firewalld deny/reject log lines ==\n' >> "$CURRENT_FILE"
  priv journalctl -k -b --no-pager -n "$KERNEL_LINES" 2>/dev/null \
    | grep -Ei 'filter_(IN|OUT)|DENIED|DROP' >> "$CURRENT_FILE" || true
  printf '\n== firewalld unit: deny/drop/reject lines ==\n' >> "$CURRENT_FILE"
  priv journalctl -u firewalld -b --no-pager -n "$JOURNAL_LINES" 2>/dev/null \
    | grep -Ei 'denied|deny|drop|reject' >> "$CURRENT_FILE" || true
  redact_file "$CURRENT_FILE"
  record_ok "firewalld-denied.txt (LogDenied setting and denied-packet lines)"
else
  record_skip "firewalld-denied.txt (journalctl or grep not installed)"
fi

# --- bounded tcpdump capture ---------------------------------------------
CAPTURE_STATUS=skipped
if ((WANT_CAPTURE == 0)); then
  record_skip "tcpdump capture (disabled by --no-capture)"
elif ! have tcpdump; then
  record_skip "tcpdump capture (tcpdump not installed)"
elif ! have timeout; then
  record_skip "tcpdump capture (timeout(1) not installed; refusing an unbounded capture)"
elif ((IS_ROOT == 0)) && ((SUDO_OK == 0)); then
  record_skip "tcpdump capture (needs root or passwordless sudo; rerun with sudo)"
elif [[ -z $IFACE ]]; then
  record_skip "tcpdump capture (no WireGuard interface detected)"
else
  printf 'Capturing up to %s UDP packets for up to %s s on %s...\n' \
    "$CAPTURE_COUNT" "$CAPTURE_SECONDS" "$IFACE"
  if ((WANT_PCAP == 1)); then
    pcap="$OUT_DIR/wg.pcap"
    capture_rc=0
    if ((IS_ROOT == 1)); then
      timeout "$CAPTURE_SECONDS" tcpdump -ni "$IFACE" -c "$CAPTURE_COUNT" -s 128 -w "$pcap" udp \
        >/dev/null 2>&1 </dev/null || capture_rc=$?
    else
      sudo -n timeout "$CAPTURE_SECONDS" tcpdump -ni "$IFACE" -c "$CAPTURE_COUNT" -s 128 -w "$pcap" udp \
        >/dev/null 2>&1 </dev/null || capture_rc=$?
    fi
    if [[ -s $pcap ]]; then
      CAPTURE_STATUS="raw pcap"
      record_ok "wg.pcap (RAW capture, NOT redacted)"
      printf 'WARNING: wg.pcap is a raw capture. It contains outer endpoint addresses and is NOT redacted.\n'
    else
      record_skip "tcpdump capture (no packets captured; exit $capture_rc)"
      if have rm; then rm -f "$pcap"; fi
    fi
  else
    new_file tcpdump-wg.txt "Bounded tcpdump capture on $IFACE (addresses redacted)"
    printf '# tcpdump -ni %s -c %s udp (max %s s)\n\n' \
      "$IFACE" "$CAPTURE_COUNT" "$CAPTURE_SECONDS" >> "$CURRENT_FILE"
    capture_rc=0
    if ((IS_ROOT == 1)); then
      timeout "$CAPTURE_SECONDS" tcpdump -ni "$IFACE" -c "$CAPTURE_COUNT" udp \
        >> "$CURRENT_FILE" 2>&1 </dev/null || capture_rc=$?
    else
      sudo -n timeout "$CAPTURE_SECONDS" tcpdump -ni "$IFACE" -c "$CAPTURE_COUNT" udp \
        >> "$CURRENT_FILE" 2>&1 </dev/null || capture_rc=$?
    fi
    if ((capture_rc == 124)); then
      printf '\n(capture stopped after %s s)\n' "$CAPTURE_SECONDS" >> "$CURRENT_FILE"
    elif ((capture_rc != 0)); then
      printf '\n(tcpdump exited %s)\n' "$capture_rc" >> "$CURRENT_FILE"
    fi
    redact_file "$CURRENT_FILE"
    if grep -q '^[0-9]' "$CURRENT_FILE" 2>/dev/null; then
      CAPTURE_STATUS="redacted text"
      record_ok "tcpdump-wg.txt (bounded capture, addresses redacted)"
    else
      CAPTURE_STATUS="empty"
      record_skip "tcpdump capture (no UDP packets seen during the window)"
    fi
  fi
fi

# --- README ---------------------------------------------------------------
{
  printf 'WiFiman Teleport diagnostics\n'
  printf '============================\n\n'
  printf 'Generated:  %s\n' "$(date -Is 2>/dev/null || date -u 2>/dev/null || printf unknown)"
  printf 'Issue:      https://github.com/iamstevedavis/wifiman-rpm/issues/29\n'
  printf 'Interface:  %s\n' "${IFACE:-none detected}"
  printf 'MTU:        %s\n' "${MTU:-unknown}"
  printf 'Privilege:  %s\n' \
    "$( ((IS_ROOT == 1)) && printf root || { ((SUDO_OK == 1)) && printf 'passwordless sudo' || printf unprivileged; } )"
  printf 'Capture:    %s\n\n' "$CAPTURE_STATUS"
  printf 'Collected:\n'
  if ((${#OK_LIST[@]})); then
    for item in "${OK_LIST[@]}"; do printf '  - %s\n' "$item"; done
  else
    printf '  (nothing)\n'
  fi
  printf '\nSkipped:\n'
  if ((${#SKIP_LIST[@]})); then
    for item in "${SKIP_LIST[@]}"; do printf '  - %s\n' "$item"; done
  else
    printf '  (nothing)\n'
  fi
  printf '\nRedaction (default output):\n'
  printf '  - WireGuard private and preshared key lines are replaced with [REDACTED];\n'
  printf '    key-shaped base64 tokens become [REDACTED-KEY].\n'
  printf '  - "endpoint:" lines from wg show are replaced with [REDACTED].\n'
  printf '  - tcpdump text output masks source/destination addresses.\n'
  printf '  - Raw .pcap output (--pcap) is NOT redacted: it contains outer endpoint\n'
  printf '    addresses even though WireGuard payloads are encrypted. Review before sharing.\n'
  printf '  - Journals are not fully redacted and may contain SSIDs, hostnames and local\n'
  printf '    addresses. Review this directory before uploading it to an issue.\n'
  printf '\nThis collector is read-only. It did not change network, firewall, service or\n'
  printf 'SELinux state.\n'
} > "$OUT_DIR/README.txt"

printf 'Wrote diagnostics to %s\n' "$OUT_DIR"
printf 'Review README.txt before sharing: keys/endpoints are redacted, but journals may contain identifiers.\n'
