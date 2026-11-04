#!/usr/bin/env bash
set -euo pipefail

# Sourced by both wrappers after selecting APP_ROOT, STATE_ROOT and RUNTIME_ROOT.
# Additional runtime items (the UI binary) are selected by each wrapper.
# Keep the mirror selective; copying the entire packaged tree broke the UI.
RUNTIME_ITEMS=(
  .env
  .env.development
  .env.staging
  wg
  wg-quick
  wg_report.sh
  wifiman-desktopd
  wireguard-go
  "${RUNTIME_EXTRA_ITEMS[@]}"
)

mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT"

sync_runtime_item() {
  local name=$1
  local src="$APP_ROOT/$name"
  local dst="$RUNTIME_ROOT/$name"

  [[ -e "$src" ]] || return 0

  rm -rf "$dst"
  # cp -a preserves the packaged mode and, where permitted, the SELinux
  # context. Avoid an extra install(1) step: it attempts a context transition
  # that is denied to the confined daemon and only prints a warning.
  cp -a "$src" "$dst"
}

# If the state file already points at the runtime copy from a prior run, the
# config is already in the right place — preserve it. Only reseed when the
# symlink is broken or the runtime copy is missing.
skip_service_sync=0
if [[ -L "$STATE_ROOT/service.json" ]]; then
  target=$(readlink -f "$STATE_ROOT/service.json" || true)
  runtime_service=$(readlink -f "$RUNTIME_ROOT/service.json" 2>/dev/null || true)
  if [[ -n "$target" && "$target" == "$runtime_service" ]]; then
    # Symlink is valid and points at the runtime copy. Ensure the runtime
    # copy exists (it may have been cleaned) but do NOT reseed — the existing
    # config must survive.
    if [[ ! -s "$RUNTIME_ROOT/service.json" ]]; then
      printf '{}\n' > "$RUNTIME_ROOT/service.json"
    fi
    # Skip the reseed + copy below; the symlink already links state → runtime.
    skip_service_sync=1
  else
    # Symlink is stale or points elsewhere — break it so we can reseed.
    rm -f "$STATE_ROOT/service.json"
  fi
fi

if [[ ${skip_service_sync:-0} -eq 0 ]]; then
  if [[ ! -s "$STATE_ROOT/service.json" ]]; then
    printf '{}\n' > "$STATE_ROOT/service.json"
  fi
fi

shopt -s dotglob nullglob
# Clean stale runtime entries on each start so old packaged artifacts do not
# linger after wrapper changes.
for existing in "$RUNTIME_ROOT"/*; do
  name=${existing##*/}
  if [[ "$name" == "service.json" ]]; then
    continue
  fi
  rm -rf "$existing"
done

for name in "${RUNTIME_ITEMS[@]}"; do
  sync_runtime_item "$name"
done

# wg-quick derives the tunnel MTU from the route to the peer endpoint and
# subtracts 80. On cellular / hotspot paths the real path MTU is much lower
# (~1190), so larger packets are silently dropped while small ones still work.
# Cap the auto-detected MTU in the runtime copy only -- never in the packaged
# file. An explicit MTU= in the wg config still wins because set_mtu_up()
# returns early in that branch. WIFIMAN_WG_MTU_CAP overrides the cap and 0
# disables it. Unrecognized wg-quick content is left untouched with a warning
# so an upstream change cannot break the mirror.
WG_QUICK_MTU_CAP_MARKER='# wifiman: WireGuard MTU cap'

cap_wg_quick_mtu() {
  local target=${1:-$RUNTIME_ROOT/wg-quick}
  local default_cap=1280
  local cap=${WIFIMAN_WG_MTU_CAP:-$default_cap}
  local tmp mode

  [[ -f "$target" ]] || return 0

  if ! [[ "$cap" =~ ^[0-9]+$ ]]; then
    printf 'wifiman-runtime: warning: ignoring invalid WIFIMAN_WG_MTU_CAP=%s (using %s)\n' \
      "$cap" "$default_cap" >&2
    cap=$default_cap
  fi
  # Base 10, so a leading zero is not read as octal by [[ -le ]].
  cap=$((10#$cap))
  # Linux removes IPv6 from links below 1280, and the daemon's UDP echo
  # check runs over IPv6 in the tunnel. A lower cap would trigger the
  # "Too many timeouts" reconnect loop.
  if (( cap > 0 && cap < 1280 )); then
    printf 'wifiman-runtime: warning: WIFIMAN_WG_MTU_CAP=%s is below the IPv6 minimum (using 1280)\n' \
      "$cap" >&2
    cap=1280
  fi

  # Already patched by an earlier run: leave it alone.
  if grep -qF "$WG_QUICK_MTU_CAP_MARKER" "$target"; then
    return 0
  fi

  # Cap disabled: keep the copied wg-quick exactly as packaged.
  if [[ "$cap" -eq 0 ]]; then
    return 0
  fi

  tmp=$(mktemp "$target.wifiman-mtu.XXXXXX" 2>/dev/null) || {
    printf 'wifiman-runtime: warning: could not create a temp file to cap wg-quick MTU in %s\n' \
      "$target" >&2
    return 0
  }

  # Write the validated cap as a literal. Reading the env var again inside
  # wg-quick would let an invalid value reach `ip link set mtu`. The mirror is
  # rebuilt on every start, so a changed override still takes effect.
  if awk -v cap="$cap" -v marker="$WG_QUICK_MTU_CAP_MARKER" '
    !patched && /cmd ip link set mtu/ && /\$\(\( mtu - 80 \)\)/ {
      print "\tmtu=$(( mtu - 80 ))"
      print "\t[[ $mtu -le " cap " ]] || mtu=" cap "  " marker
      print "\tcmd ip link set mtu \"$mtu\" up dev \"$INTERFACE\""
      patched = 1
      next
    }
    { print }
    END { exit(patched ? 0 : 1) }
  ' "$target" > "$tmp"; then
    mode=$(stat -c '%a' "$target" 2>/dev/null || true)
    chmod "${mode:-0755}" "$tmp"
    mv -f "$tmp" "$target"
    # The rewrite creates a new inode, so it would otherwise inherit the
    # writable state type and stop being executable under the dedicated
    # SELinux policy. Reuse the packaged wg helper context; this is a no-op
    # on hosts without SELinux tooling.
    if command -v chcon >/dev/null 2>&1; then
      chcon --reference="$RUNTIME_ROOT/wg" "$target" 2>/dev/null || true
    fi
  else
    rm -f "$tmp"
    printf 'wifiman-runtime: warning: unexpected wg-quick content; leaving MTU uncapped in %s\n' \
      "$target" >&2
  fi
}

cap_wg_quick_mtu "$RUNTIME_ROOT/wg-quick"

# Preserve service.json across runs, but avoid copying when source and target
# already match. When the symlink is already valid (skip_service_sync), the
# state file IS the runtime file — no copy or relink needed.
if [[ ${skip_service_sync:-0} -eq 0 ]]; then
  if [[ ! -e "$RUNTIME_ROOT/service.json" ]] || ! cmp -s "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"; then
    cp -f "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"
  fi
  ln -sfn "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
fi
rm -f "$STATE_ROOT/service.json.tmp"

export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"
