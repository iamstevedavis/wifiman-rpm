#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

HELPER="$ROOT_DIR/scripts/wifiman-runtime.sh"
mkdir -p "$WORK_DIR/empty-app" "$WORK_DIR/state"

# Trimmed copy of the shipped wg-quick MTU handling, including the fallback
# that the runtime mirror patches. Keep it in sync with the real script so the
# patch sees realistic content.
make_wg_quick_fixture() {
  local path=$1
  cat > "$path" <<'FIXTURE'
#!/usr/bin/env bash
INTERFACE=${INTERFACE:-wg0}

set_mtu_up() {
	local mtu=0 endpoint output
	if [[ -n $MTU ]]; then
		cmd ip link set mtu "$MTU" up dev "$INTERFACE"
		return
	fi
	while read -r _ endpoint; do
		[[ $endpoint =~ ^\[?([a-z0-9:.]+)\]?:[0-9]+$ ]] || continue
		output="$(ip route get "${BASH_REMATCH[1]}" || true)"
		[[ ( $output =~ mtu\ ([0-9]+) || ( $output =~ dev\ ([^ ]+) && $(ip link show dev "${BASH_REMATCH[1]}") =~ mtu\ ([0-9]+) ) ) && ${BASH_REMATCH[1]} -gt $mtu ]] && mtu="${BASH_REMATCH[1]}"
	done < <(wg show "$INTERFACE" endpoints)
	[[ $mtu -gt 0 ]] || mtu=1500
	cmd ip link set mtu $(( mtu - 80 )) up dev "$INTERFACE"
}

cmd() {
	printf '%s\n' "$*" >> "$CALL_LOG"
}
FIXTURE
  chmod 0755 "$path"
}

# Stubs for the commands set_mtu_up() inspects: a 1500-byte path, i.e. the
# auto-detected 1420 that is too large on cellular / hotspot links.
ip() {
  printf '1.2.3.4 via 192.168.1.1 dev wlan0 src 192.168.1.20 mtu 1500\n'
}

wg() {
  printf 'peer-key\t1.2.3.4:51820\n'
}

# Source the runtime helper in a throwaway shell and invoke the patch on one
# file. $2 is the cap; omit it to exercise the default.
patch_fixture() {
  local fixture_path=$1 cap=${2-__unset__}
  (
    set -euo pipefail
    APP_ROOT="$WORK_DIR/empty-app"
    STATE_ROOT="$WORK_DIR/state"
    RUNTIME_ROOT="$STATE_ROOT/app-root"
    RUNTIME_EXTRA_ITEMS=()
    export APP_ROOT STATE_ROOT RUNTIME_ROOT RUNTIME_EXTRA_ITEMS
    if [[ "$cap" == "__unset__" ]]; then
      unset WIFIMAN_WG_MTU_CAP || true
    else
      WIFIMAN_WG_MTU_CAP="$cap"
      export WIFIMAN_WG_MTU_CAP
    fi
    # shellcheck disable=SC1090
    source "$HELPER"
    cap_wg_quick_mtu "$fixture_path"
  )
}

# Run the fixture's set_mtu_up() and return the ip command it issued last.
run_fixture_mtu() {
  CALL_LOG="$WORK_DIR/calls.txt"
  export CALL_LOG
  : > "$CALL_LOG"
  # wg-quick itself runs without nounset.
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set_mtu_up
  set -u
  tail -n 1 "$CALL_LOG"
}

mtu_guard_count() {
  { grep -c '\$mtu -le' "$1" || true; }
}

# --- cap applied to a fresh copy ------------------------------------------
make_wg_quick_fixture "$WORK_DIR/wg-quick"
cp "$WORK_DIR/wg-quick" "$WORK_DIR/pristine"
patch_fixture "$WORK_DIR/wg-quick"

test -x "$WORK_DIR/wg-quick"
test "$(mtu_guard_count "$WORK_DIR/wg-quick")" -eq 1
test "$(run_fixture_mtu "$WORK_DIR/wg-quick")" = 'ip link set mtu 1280 up dev wg0'

# --- rerun is idempotent ---------------------------------------------------
sha_before=$(sha256sum "$WORK_DIR/wg-quick" | cut -d' ' -f1)
patch_fixture "$WORK_DIR/wg-quick"
sha_after=$(sha256sum "$WORK_DIR/wg-quick" | cut -d' ' -f1)
test "$sha_before" = "$sha_after"
test "$(mtu_guard_count "$WORK_DIR/wg-quick")" -eq 1
test -x "$WORK_DIR/wg-quick"
test "$(run_fixture_mtu "$WORK_DIR/wg-quick")" = 'ip link set mtu 1280 up dev wg0'

# --- explicit MTU= still wins ---------------------------------------------
test "$(MTU=1180 run_fixture_mtu "$WORK_DIR/wg-quick")" = 'ip link set mtu 1180 up dev wg0'

# --- WIFIMAN_WG_MTU_CAP overrides the cap ---------------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/custom"
patch_fixture "$WORK_DIR/custom" 1300
test "$(run_fixture_mtu "$WORK_DIR/custom")" = 'ip link set mtu 1300 up dev wg0'

# --- WIFIMAN_WG_MTU_CAP=0 disables the cap --------------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/disabled"
patch_fixture "$WORK_DIR/disabled" 0
cmp "$WORK_DIR/pristine" "$WORK_DIR/disabled"
test "$(mtu_guard_count "$WORK_DIR/disabled")" -eq 0
test "$(run_fixture_mtu "$WORK_DIR/disabled")" = 'ip link set mtu 1420 up dev wg0'

# --- the patched file uses the literal cap, not the env at tunnel-up time ---
test "$(WIFIMAN_WG_MTU_CAP=abc run_fixture_mtu "$WORK_DIR/wg-quick")" = 'ip link set mtu 1280 up dev wg0'
if grep -q 'WIFIMAN_WG_MTU_CAP' "$WORK_DIR/wg-quick"; then
  echo "patched wg-quick must not read WIFIMAN_WG_MTU_CAP at runtime" >&2
  exit 1
fi

# --- an invalid override falls back to the default cap ----------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/invalid"
patch_fixture "$WORK_DIR/invalid" abc 2> "$WORK_DIR/invalid-stderr.txt"
grep -q 'ignoring invalid WIFIMAN_WG_MTU_CAP=abc' "$WORK_DIR/invalid-stderr.txt"
test "$(run_fixture_mtu "$WORK_DIR/invalid")" = 'ip link set mtu 1280 up dev wg0'

# --- caps below 1280 would drop IPv6 on the tunnel; clamp with a warning ---
cp "$WORK_DIR/pristine" "$WORK_DIR/low"
patch_fixture "$WORK_DIR/low" 1200 2> "$WORK_DIR/low-stderr.txt"
grep -q 'below the IPv6 minimum' "$WORK_DIR/low-stderr.txt"
test "$(run_fixture_mtu "$WORK_DIR/low")" = 'ip link set mtu 1280 up dev wg0'

# --- a leading zero is decimal, not octal ---------------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/leading-zero"
patch_fixture "$WORK_DIR/leading-zero" 01300
test "$(run_fixture_mtu "$WORK_DIR/leading-zero")" = 'ip link set mtu 1300 up dev wg0'

# --- unrecognized content is left unmodified with a warning ----------------
printf '#!/bin/sh\necho unexpected upstream change\n' > "$WORK_DIR/weird"
chmod 0755 "$WORK_DIR/weird"
cp "$WORK_DIR/weird" "$WORK_DIR/weird-pristine"
if ! patch_fixture "$WORK_DIR/weird" 2> "$WORK_DIR/weird-stderr.txt"; then
  echo "patch must not fail on unrecognized wg-quick content" >&2
  exit 1
fi
cmp "$WORK_DIR/weird-pristine" "$WORK_DIR/weird"
test -x "$WORK_DIR/weird"
grep -qi 'warning' "$WORK_DIR/weird-stderr.txt"
grep -q 'uncapped' "$WORK_DIR/weird-stderr.txt"

# --- the runtime mirror patches the copy, never the packaged file ----------
APP_ROOT="$WORK_DIR/installed-app"
STATE_ROOT="$WORK_DIR/installed-state"
mkdir -p "$APP_ROOT" "$STATE_ROOT"
make_wg_quick_fixture "$APP_ROOT/wg-quick"
cp "$APP_ROOT/wg-quick" "$WORK_DIR/packaged-pristine"
cat > "$APP_ROOT/wifiman-desktopd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$APP_ROOT/wifiman-desktopd"

APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh"

RUNTIME_ROOT="$STATE_ROOT/app-root"
cmp "$WORK_DIR/packaged-pristine" "$APP_ROOT/wg-quick"
test -x "$RUNTIME_ROOT/wg-quick"
test "$(mtu_guard_count "$RUNTIME_ROOT/wg-quick")" -eq 1
test "$(run_fixture_mtu "$RUNTIME_ROOT/wg-quick")" = 'ip link set mtu 1280 up dev wg0'

echo "wg-quick MTU cap test passed"
