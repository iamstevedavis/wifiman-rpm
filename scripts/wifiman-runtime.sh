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

# Under the dedicated policy the daemon may write the runtime mirror but not
# the packaged tree. Leave copied files at the kernel-selected runtime type
# instead of preserving the packaged read-only context. Under the legacy
# policy the copies must keep lib_t so init_t can execute them.
current_domain=
{ read -r current_domain < /proc/self/attr/current; } 2>/dev/null || true
is_wifiman_domain=0
[[ "$current_domain" == *wifiman_t* ]] && is_wifiman_domain=1

sync_runtime_item() {
  local name=$1
  local src="$APP_ROOT/$name"
  local dst="$RUNTIME_ROOT/$name"

  [[ -e "$src" ]] || return 0

  local -a cp_args=(-a)

  if (( is_wifiman_domain )); then
    cp_args+=(--no-preserve=context)
  fi

  rm -rf "$dst"
  # Avoid an extra install(1) step: it attempts a context transition that is
  # denied to the confined daemon and only prints a warning.
  cp "${cp_args[@]}" "$src" "$dst"
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
# TCP MSS clamp marker. Kept separate from the MTU cap so either can be
# disabled independently.
WG_QUICK_MSS_CLAMP_MARKER='# wifiman: TCP MSS clamp'

cap_wg_quick_mtu() {
  local target=${1:-$RUNTIME_ROOT/wg-quick}
  local default_cap=1280
  local cap=${WIFIMAN_WG_MTU_CAP:-$default_cap}
  local tmp mode backup

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
    # Write through the existing target so it keeps its runtime-helper label
    # (or receives the helper filename transition if it has to be created).
    # Replacing it with mv would create a writable-state inode and require a
    # relabel grant.
    # The write is not atomic, so keep the original content and restore it if
    # the write fails part-way (for example "Text file busy"). The mirror is
    # rebuilt on every start, which also heals a write cut short by a crash.
    backup=$(mktemp "$target.wifiman-mtu-orig.XXXXXX" 2>/dev/null) || backup=
    if [[ -n "$backup" ]]; then
      cat "$target" > "$backup" 2>/dev/null || { rm -f "$backup"; backup=; }
    fi
    if cat "$tmp" > "$target" 2>/dev/null; then
      chmod "${mode:-0755}" "$target"
    else
      if [[ -n "$backup" ]]; then
        cat "$backup" > "$target" 2>/dev/null || true
      fi
      printf 'wifiman-runtime: warning: could not rewrite %s; leaving MTU uncapped\n' \
        "$target" >&2
    fi
    rm -f "$tmp" ${backup:+"$backup"}
  else
    rm -f "$tmp"
    printf 'wifiman-runtime: warning: unexpected wg-quick content; leaving MTU uncapped in %s\n' \
      "$target" >&2
  fi
}

# With the link capped at 1280, TCP still advertises an MSS derived from that
# MTU (1240 for IPv4). On the measured hotspot path only about 1190-1200 bytes
# of tunnel payload fit, so those larger segments are silently dropped. Clamp
# the advertised MSS while the tunnel is up and remove the rule when it goes
# down. The default keeps both IPv4 (1180-byte) and IPv6 (1200-byte) packets
# inside that window.
#
# Only the runtime copy is patched. The clamp prefers iptables/ip6tables
# because the dedicated wifiman_t policy already allows iptables_exec_t (and
# Fedora labels nft the same way); nft is the fallback when iptables is absent.
# If neither tool is available, or any command fails, the tunnel still comes
# up: every firewall command is optional and its errors are discarded.
# WIFIMAN_TCP_MSS_CLAMP overrides the MSS and 0 disables the clamp.
cap_wg_quick_mss() {
  local target=${1:-$RUNTIME_ROOT/wg-quick}
  local default_mss=1140
  local min_mss=536
  local max_mss=65535
  local mss=${WIFIMAN_TCP_MSS_CLAMP:-$default_mss}
  local insertion_marker='# ~~ function override insertion point ~~'
  local tmp snippet mode backup

  [[ -f "$target" ]] || return 0

  if ! [[ "$mss" =~ ^[0-9]+$ ]]; then
    printf 'wifiman-runtime: warning: ignoring invalid WIFIMAN_TCP_MSS_CLAMP=%s (using %s)\n' \
      "$mss" "$default_mss" >&2
    mss=$default_mss
  fi
  # Base 10, so a leading zero is not read as octal by the arithmetic below.
  mss=$((10#$mss))
  if (( mss > 0 && mss < min_mss )); then
    printf 'wifiman-runtime: warning: WIFIMAN_TCP_MSS_CLAMP=%s is below the TCP minimum (using %s)\n' \
      "$mss" "$min_mss" >&2
    mss=$min_mss
  elif (( mss > max_mss )); then
    printf 'wifiman-runtime: warning: WIFIMAN_TCP_MSS_CLAMP=%s is above the TCP maximum (using %s)\n' \
      "$mss" "$default_mss" >&2
    mss=$default_mss
  fi

  # Already patched by an earlier run: leave it alone.
  if grep -qF "$WG_QUICK_MSS_CLAMP_MARKER" "$target"; then
    return 0
  fi

  # Clamp disabled: keep the copied wg-quick exactly as packaged.
  if [[ "$mss" -eq 0 ]]; then
    return 0
  fi

  # The bundled wg-quick exposes this insertion point after its function
  # definitions and before the command dispatch. The two call sites are the
  # same ones a PostUp/PostDown hook would use: after the link is up and before
  # del_if() tears it down (including the failure trap).
  if ! grep -qxF "$insertion_marker" "$target" ||
    ! grep -qE '^[[:space:]]*set_mtu_up$' "$target" ||
    ! grep -qE '^del_if\(\) \{' "$target"; then
    printf 'wifiman-runtime: warning: unexpected wg-quick content; leaving TCP MSS unclamped in %s\n' \
      "$target" >&2
    return 0
  fi

  snippet=$(mktemp "$target.wifiman-mss-snippet.XXXXXX" 2>/dev/null) || {
    printf 'wifiman-runtime: warning: could not create a temp file to clamp TCP MSS in %s\n' \
      "$target" >&2
    return 0
  }

  if ! sed "s/@MSS@/$mss/g" > "$snippet" <<'EOF'
# wifiman: TCP MSS clamp
# Inserted before the command dispatch by wifiman-runtime.sh. The rule is
# removed by del_if(), which runs on down and on the failure trap.
wifiman_mss_clamp() {
	local mss=@MSS@ table
	if command -v iptables >/dev/null 2>&1; then
		iptables -t mangle -C POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" >/dev/null 2>&1 ||
			iptables -t mangle -A POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" >/dev/null 2>&1 || true
		if command -v ip6tables >/dev/null 2>&1; then
			ip6tables -t mangle -C POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" >/dev/null 2>&1 ||
				ip6tables -t mangle -A POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss" >/dev/null 2>&1 || true
		fi
	elif command -v nft >/dev/null 2>&1; then
		table="wifiman_mss_${INTERFACE//[^a-zA-Z0-9_]/_}"
		nft delete table inet "$table" >/dev/null 2>&1 || true
		if nft add table inet "$table" >/dev/null 2>&1 &&
			nft "add chain inet $table postrouting { type filter hook postrouting priority mangle; }" >/dev/null 2>&1 &&
			nft add rule inet "$table" postrouting oifname "$INTERFACE" tcp flags syn tcp option maxseg size gt "$mss" tcp option maxseg size set "$mss" >/dev/null 2>&1; then
			:
		else
			nft delete table inet "$table" >/dev/null 2>&1 || true
		fi
	fi
	return 0
}

wifiman_mss_unclamp() {
	local table
	# Remove whichever backend was used, even if the PATH changed while the
	# tunnel was up.
	if command -v iptables >/dev/null 2>&1; then
		iptables -t mangle -D POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "@MSS@" >/dev/null 2>&1 || true
	fi
	if command -v ip6tables >/dev/null 2>&1; then
		ip6tables -t mangle -D POSTROUTING -o "$INTERFACE" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "@MSS@" >/dev/null 2>&1 || true
	fi
	if command -v nft >/dev/null 2>&1; then
		table="wifiman_mss_${INTERFACE//[^a-zA-Z0-9_]/_}"
		nft delete table inet "$table" >/dev/null 2>&1 || true
	fi
	return 0
}

EOF
  then
    rm -f "$snippet"
    printf 'wifiman-runtime: warning: could not build the TCP MSS clamp for %s\n' \
      "$target" >&2
    return 0
  fi

  tmp=$(mktemp "$target.wifiman-mss.XXXXXX" 2>/dev/null) || {
    rm -f "$snippet"
    printf 'wifiman-runtime: warning: could not create a temp file to clamp TCP MSS in %s\n' \
      "$target" >&2
    return 0
  }

  if ! awk -v snippet="$snippet" '
    $0 == "# ~~ function override insertion point ~~" {
      while ((getline line < snippet) > 0) print line
      close(snippet)
    }
    /^[[:space:]]*set_mtu_up$/ {
      print
      print "\twifiman_mss_clamp"
      next
    }
    /^del_if\(\) \{/ {
      print
      print "\twifiman_mss_unclamp"
      next
    }
    { print }
  ' "$target" > "$tmp"; then
    rm -f "$snippet" "$tmp"
    printf 'wifiman-runtime: warning: could not patch TCP MSS clamp into %s\n' \
      "$target" >&2
    return 0
  fi
  rm -f "$snippet"

  mode=$(stat -c '%a' "$target" 2>/dev/null || true)
  # As with the MTU cap, write through the existing target so it keeps its
  # runtime-helper label, and keep a backup in case the write is cut short.
  backup=$(mktemp "$target.wifiman-mss-orig.XXXXXX" 2>/dev/null) || backup=
  if [[ -n "$backup" ]]; then
    cat "$target" > "$backup" 2>/dev/null || { rm -f "$backup"; backup=; }
  fi
  if cat "$tmp" > "$target" 2>/dev/null; then
    chmod "${mode:-0755}" "$target"
  else
    if [[ -n "$backup" ]]; then
      cat "$backup" > "$target" 2>/dev/null || true
    fi
    printf 'wifiman-runtime: warning: could not rewrite %s; leaving TCP MSS unclamped\n' \
      "$target" >&2
  fi
  rm -f "$tmp" ${backup:+"$backup"}
}

cap_wg_quick_mtu "$RUNTIME_ROOT/wg-quick"
cap_wg_quick_mss "$RUNTIME_ROOT/wg-quick"

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
