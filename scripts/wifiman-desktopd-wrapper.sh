#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}
STATE_ROOT=${STATE_ROOT:-/var/lib/wifiman-desktop}
RUNTIME_ROOT="$STATE_ROOT/app-root"

# Keep the daemon runtime mirror intentionally selective. Mirroring the whole
# packaged tree previously pulled in junk artifacts and caused regressions.
RUNTIME_ITEMS=(
  .env
  .env.development
  .env.staging
  compat
  wg
  wg-quick
  wg_report.sh
  wifiman-desktopd
  wireguard-go
)

mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT"

sync_runtime_item() {
  local name=$1
  local src="$APP_ROOT/$name"
  local dst="$RUNTIME_ROOT/$name"

  [[ -e "$src" ]] || return 0

  rm -rf "$dst"
  if [[ -d "$src" ]]; then
    cp -a "$src" "$dst"
  else
    install -D -m 0755 /dev/null "$dst"
    cp -a "$src" "$dst"
  fi
}

# If the state file already points at the runtime copy from a prior run, the
# config is already in the right place — preserve it. Only reseed when the
# symlink is broken or the runtime copy is missing.
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

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wifiman-desktopd" "$@"
