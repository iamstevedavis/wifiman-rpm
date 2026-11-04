#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

HELPER="$ROOT_DIR/scripts/wifiman-runtime.sh"
mkdir -p "$WORK_DIR/empty-app" "$WORK_DIR/state" "$WORK_DIR/bin-iptables" \
  "$WORK_DIR/bin-nft" "$WORK_DIR/bin-none"
CALL_LOG="$WORK_DIR/calls.txt"
IPTABLES_STATE="$WORK_DIR/iptables-state.txt"
export CALL_LOG IPTABLES_STATE
: > "$CALL_LOG"
: > "$IPTABLES_STATE"

# wg-quick invokes its own directory first on PATH, so the stubs must not
# accidentally shadow the firewall commands under test.
ln -s "$(command -v bash)" "$WORK_DIR/bin-iptables/bash"
ln -s "$(command -v bash)" "$WORK_DIR/bin-nft/bash"
ln -s "$(command -v bash)" "$WORK_DIR/bin-none/bash"

cat > "$WORK_DIR/bin-iptables/iptables" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tool=${0##*/}
full=$*
printf '%s %s\n' "$tool" "$full" >> "$CALL_LOG"
[[ ${1:-} == -t && ${2:-} == mangle ]] || exit 0
shift 2
case "${1:-}" in
-C)
  # A rule exists only after an -A added it, so a second clamp is a no-op.
  key="$tool ${full/-C/-A}"
  while IFS= read -r line; do
    [[ "$line" == "$key" ]] && exit 0
  done < "$IPTABLES_STATE"
  exit 1
  ;;
-A)
  printf '%s\n' "$tool $full" >> "$IPTABLES_STATE"
  ;;
esac
exit 0
EOF
chmod +x "$WORK_DIR/bin-iptables/iptables"
ln -s iptables "$WORK_DIR/bin-iptables/ip6tables"

cat > "$WORK_DIR/bin-nft/nft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nft %s\n' "$*" >> "$CALL_LOG"
exit 0
EOF
chmod +x "$WORK_DIR/bin-nft/nft"

# Trimmed but realistic bundled wg-quick: the function override insertion point
# and the set_mtu_up/del_if call sites that wifiman-runtime.sh patches.
make_wg_quick_fixture() {
  local path=$1
  cat > "$path" <<'FIXTURE'
#!/usr/bin/env bash
set -e -o pipefail
INTERFACE=${INTERFACE:-wg0}
POST_UP=( )
PRE_DOWN=( )

cmd() {
	printf '%s\n' "$*" >> "$CALL_LOG"
}

execute_hooks() {
	local hook
	for hook in "$@"; do
		hook="${hook//%i/$INTERFACE}"
		(eval "$hook")
	done
}

set_mtu_up() {
	local mtu=1500
	cmd ip link set mtu $(( mtu - 80 )) up dev "$INTERFACE"
}

cmd_up() {
	set_mtu_up
	execute_hooks "${POST_UP[@]}"
}

del_if() {
	cmd ip link delete dev "$INTERFACE"
}

cmd_down() {
	execute_hooks "${PRE_DOWN[@]}"
	del_if
}

# ~~ function override insertion point ~~
FIXTURE
  chmod 0755 "$path"
}

patch_fixture() {
  local fixture_path=$1 mss=${2-__unset__}
  (
    set -euo pipefail
    APP_ROOT="$WORK_DIR/empty-app"
    STATE_ROOT="$WORK_DIR/state"
    RUNTIME_ROOT="$STATE_ROOT/app-root"
    RUNTIME_EXTRA_ITEMS=()
    export APP_ROOT STATE_ROOT RUNTIME_ROOT RUNTIME_EXTRA_ITEMS
    if [[ "$mss" == "__unset__" ]]; then
      unset WIFIMAN_TCP_MSS_CLAMP || true
    else
      WIFIMAN_TCP_MSS_CLAMP="$mss"
      export WIFIMAN_TCP_MSS_CLAMP
    fi
    # shellcheck disable=SC1090
    source "$HELPER"
    cap_wg_quick_mss "$fixture_path"
  )
}

# Source one patched fixture with only the selected tool directory available,
# then call a function from it. This models wg-quick's PATH without relying on
# whichever firewall tool the test host happens to have.
run_in_fixture() {
  local fixture_path=$1 tool_dir=$2 function_name=$3
  (
    set +u
    PATH="$tool_dir"
    export PATH CALL_LOG IPTABLES_STATE
    : > "$CALL_LOG"
    # Keep IPTABLES_STATE between calls so a second clamp exercises the -C
    # check instead of adding a duplicate rule.
    # shellcheck disable=SC1090
    source "$fixture_path"
    INTERFACE=wg0
    "$function_name"
  )
}

mss_value_in() {
  sed -n 's/^[[:space:]]*local mss=\([0-9][0-9]*\) table$/\1/p' "$1" | head -n 1
}

# --- default clamp is inserted with literal MSS ---------------------------
make_wg_quick_fixture "$WORK_DIR/wg-quick"
cp "$WORK_DIR/wg-quick" "$WORK_DIR/pristine"
patch_fixture "$WORK_DIR/wg-quick"

test -x "$WORK_DIR/wg-quick"
grep -qF '# wifiman: TCP MSS clamp' "$WORK_DIR/wg-quick"
test "$(mss_value_in "$WORK_DIR/wg-quick")" = 1140
test "$(grep -c '^[[:space:]]*wifiman_mss_clamp$' "$WORK_DIR/wg-quick")" -eq 1
test "$(grep -c '^[[:space:]]*wifiman_mss_unclamp$' "$WORK_DIR/wg-quick")" -eq 1
bash -n "$WORK_DIR/wg-quick"

# --- up adds the rule, a second up does not duplicate it, down removes it --
run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-iptables" cmd_up
grep -q 'ip link set mtu .* up dev wg0' "$CALL_LOG"
test "$(grep -c -- '^iptables -t mangle -A POSTROUTING -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1140$' "$CALL_LOG")" -eq 1
test "$(grep -c -- '^ip6tables -t mangle -A POSTROUTING -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1140$' "$CALL_LOG")" -eq 1
run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-iptables" wifiman_mss_clamp
test "$(grep -c -- '-A POSTROUTING' "$CALL_LOG")" -eq 0
grep -q -- '^iptables -t mangle -C POSTROUTING' "$CALL_LOG"
grep -q -- '^ip6tables -t mangle -C POSTROUTING' "$CALL_LOG"

run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-iptables" cmd_down
grep -q -- '^iptables -t mangle -D POSTROUTING -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1140$' "$CALL_LOG"
grep -q -- '^ip6tables -t mangle -D POSTROUTING -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1140$' "$CALL_LOG"
grep -q 'ip link delete dev wg0' "$CALL_LOG"

# --- missing firewall tools never break tunnel setup ----------------------
run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-none" cmd_up
! grep -q 'iptables\|nft ' "$CALL_LOG"
grep -q 'ip link set mtu .* up dev wg0' "$CALL_LOG"

# --- nft is used only when iptables is unavailable ------------------------
run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-nft" cmd_up
grep -q 'nft delete table inet wifiman_mss_wg0' "$CALL_LOG"
grep -q 'nft add table inet wifiman_mss_wg0' "$CALL_LOG"
grep -q 'nft add chain inet wifiman_mss_wg0 postrouting' "$CALL_LOG"
grep -q 'nft add rule inet wifiman_mss_wg0 postrouting oifname wg0 tcp flags syn tcp option maxseg size set 1140' "$CALL_LOG"

run_in_fixture "$WORK_DIR/wg-quick" "$WORK_DIR/bin-nft" cmd_down
grep -q 'nft delete table inet wifiman_mss_wg0' "$CALL_LOG"

# --- rerun is idempotent ---------------------------------------------------
sha_before=$(sha256sum "$WORK_DIR/wg-quick" | cut -d' ' -f1)
patch_fixture "$WORK_DIR/wg-quick"
sha_after=$(sha256sum "$WORK_DIR/wg-quick" | cut -d' ' -f1)
test "$sha_before" = "$sha_after"
test -x "$WORK_DIR/wg-quick"

# --- custom MSS ------------------------------------------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/custom"
patch_fixture "$WORK_DIR/custom" 1200
test "$(mss_value_in "$WORK_DIR/custom")" = 1200

# --- WIFIMAN_TCP_MSS_CLAMP=0 disables the clamp ----------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/disabled"
patch_fixture "$WORK_DIR/disabled" 0
cmp "$WORK_DIR/pristine" "$WORK_DIR/disabled"
! grep -qF '# wifiman: TCP MSS clamp' "$WORK_DIR/disabled"

# --- invalid / out-of-range values fall back with a warning ---------------
cp "$WORK_DIR/pristine" "$WORK_DIR/invalid"
patch_fixture "$WORK_DIR/invalid" abc 2> "$WORK_DIR/invalid.err"
grep -q 'ignoring invalid WIFIMAN_TCP_MSS_CLAMP=abc' "$WORK_DIR/invalid.err"
test "$(mss_value_in "$WORK_DIR/invalid")" = 1140

cp "$WORK_DIR/pristine" "$WORK_DIR/low"
patch_fixture "$WORK_DIR/low" 500 2> "$WORK_DIR/low.err"
grep -q 'below the TCP minimum' "$WORK_DIR/low.err"
test "$(mss_value_in "$WORK_DIR/low")" = 536

cp "$WORK_DIR/pristine" "$WORK_DIR/high"
patch_fixture "$WORK_DIR/high" 70000 2> "$WORK_DIR/high.err"
grep -q 'above the TCP maximum' "$WORK_DIR/high.err"
test "$(mss_value_in "$WORK_DIR/high")" = 1140

# --- a leading zero is decimal, not octal ---------------------------------
cp "$WORK_DIR/pristine" "$WORK_DIR/leading-zero"
patch_fixture "$WORK_DIR/leading-zero" 01200
test "$(mss_value_in "$WORK_DIR/leading-zero")" = 1200

# --- unrecognized content is left unmodified with a warning ---------------
printf '#!/bin/sh\necho upstream change\n' > "$WORK_DIR/weird"
chmod 0755 "$WORK_DIR/weird"
cp "$WORK_DIR/weird" "$WORK_DIR/weird-pristine"
patch_fixture "$WORK_DIR/weird" 2> "$WORK_DIR/weird.err"
cmp "$WORK_DIR/weird-pristine" "$WORK_DIR/weird"
grep -q 'leaving TCP MSS unclamped' "$WORK_DIR/weird.err"

# --- the runtime mirror patches the copy and composes with the MTU cap ----
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
grep -qF '# wifiman: WireGuard MTU cap' "$RUNTIME_ROOT/wg-quick"
grep -qF '# wifiman: TCP MSS clamp' "$RUNTIME_ROOT/wg-quick"
test "$(mss_value_in "$RUNTIME_ROOT/wg-quick")" = 1140
bash -n "$RUNTIME_ROOT/wg-quick"

# --- the clamp can be disabled independently of the MTU cap ---------------
STATE_ROOT="$WORK_DIR/installed-state-no-mtu"
mkdir -p "$STATE_ROOT"
APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" WIFIMAN_WG_MTU_CAP=0 \
  WIFIMAN_TCP_MSS_CLAMP=1200 bash "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh"
NO_MTU_RUNTIME="$STATE_ROOT/app-root"
! grep -qF '# wifiman: WireGuard MTU cap' "$NO_MTU_RUNTIME/wg-quick"
grep -qF '# wifiman: TCP MSS clamp' "$NO_MTU_RUNTIME/wg-quick"
test "$(mss_value_in "$NO_MTU_RUNTIME/wg-quick")" = 1200

echo "wg-quick TCP MSS clamp test passed"
