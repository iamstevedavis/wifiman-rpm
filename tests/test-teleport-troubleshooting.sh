#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DOC="$ROOT_DIR/docs/teleport-troubleshooting.md"
README="$ROOT_DIR/README.md"
COLLECTOR="$ROOT_DIR/scripts/collect-wifiman-debug-logs.sh"

test -f "$DOC"
test -x "$COLLECTOR"
bash -n "$COLLECTOR"

# README must point at the troubleshooting page.
grep -q '^## Teleport / WireGuard troubleshooting$' "$README"
grep -q 'docs/teleport-troubleshooting.md' "$README"

# The page must keep the capture steps that issue #27 needs. These are the
# commands a tester is asked to run, not an assertion that they fix anything.
for needle in \
  'TELEPORT_UDP_ECHO_FAILED' \
  '0 B received' \
  'wg show all transfer' \
  'wg show all latest-handshakes' \
  'ip -6 route show table all' \
  'NRestarts' \
  'firewall-cmd --set-log-denied=all' \
  'firewall-cmd --set-log-denied=off' \
  'LogDenied' \
  'collect-wifiman-debug-logs.sh' \
  'resolvconf' \
  'sysctl_net_t' \
  'Do not run the packaged `wg-quick` directly'
do
  grep -Fq -- "$needle" "$DOC" || {
    echo "missing troubleshooting step: $needle" >&2
    exit 1
  }
done

# The page is deliberately honest: no claim that the RPM fixed the upstream
# reconnect loop.
if grep -Eqi 'this (change|PR|package) fixes|closes #27|fixes #27' "$DOC"; then
  echo "troubleshooting page must not claim the reconnect loop is fixed" >&2
  exit 1
fi
grep -Fq 'Whether that ordering change' "$DOC"
grep -Fq 'not proven' "$DOC"

# The collector is the copy-paste fallback for a failing attempt.
for needle in \
  '===== SERVICE COUNTERS =====' \
  'NRestarts' \
  '===== WIREGUARD =====' \
  'wg show all transfer' \
  'ip -6 route show table all' \
  '===== FIREWALL =====' \
  'firewall-cmd --get-active-zones' \
  'firewall-cmd --get-log-denied' \
  'nft list ruleset' \
  'sysctl_net_t'
do
  grep -Fq -- "$needle" "$COLLECTOR" || {
    echo "collector missing diagnostic: $needle" >&2
    exit 1
  }
done

# The collector's output is meant to be shared, so it must never run a wg
# command that prints a private key. Stub wg with a fake key in "dump" and
# "showconf" output and assert the key never reaches the log.
for forbidden in 'wg show all dump' 'wg showconf'; do
  if grep -v '^[[:space:]]*#' "$COLLECTOR" | grep -Fq -- "$forbidden"; then
    echo "collector must not run: $forbidden" >&2
    exit 1
  fi
done
if grep -Eq '^[[:space:]]*sudo wg (show [^|]*dump|showconf)' "$DOC"; then
  echo "troubleshooting page must not tell users to print private keys" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/bin"
FAKE_KEY='FAKEPRIVATEKEYFAKEPRIVATEKEYFAKEPRIVATEKEY0='
cat > "$WORK_DIR/bin/wg" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK_DIR/wg-calls.log"
case "\$*" in
  *dump*|*showconf*) printf 'wg0\t$FAKE_KEY\tpubkey\t51820\toff\n' ;;
  *) printf 'interface: wg0\n  private key: (hidden)\n' ;;
esac
STUB
cat > "$WORK_DIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
chmod +x "$WORK_DIR/bin/wg" "$WORK_DIR/bin/sudo"

PATH="$WORK_DIR/bin:$PATH" OUT="$WORK_DIR/debug.log" JOURNAL_LINES=1 APP_LOG_LINES=1 \
  bash "$COLLECTOR" >/dev/null 2>&1 || true
test -s "$WORK_DIR/debug.log"
test -s "$WORK_DIR/wg-calls.log"
if grep -Fq "$FAKE_KEY" "$WORK_DIR/debug.log"; then
  echo "collector log leaked a WireGuard private key" >&2
  exit 1
fi
if grep -Eq 'dump|showconf' "$WORK_DIR/wg-calls.log"; then
  echo "collector invoked a wg command that prints private keys" >&2
  exit 1
fi

echo "teleport troubleshooting test passed"
