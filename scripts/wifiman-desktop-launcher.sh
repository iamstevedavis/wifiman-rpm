#!/usr/bin/bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}

# Desktop launches must use per-user writable state rather than /var/lib.
if [[ -z ${STATE_ROOT:-} ]]; then
  if [[ -n ${XDG_STATE_HOME:-} ]]; then
    STATE_ROOT="$XDG_STATE_HOME/wifiman-desktop"
  elif [[ -n ${HOME:-} ]]; then
    STATE_ROOT="$HOME/.local/state/wifiman-desktop"
  else
    STATE_ROOT=/tmp/wifiman-desktop
  fi
fi
RUNTIME_ROOT="$STATE_ROOT/app-root"

# Keep the runtime mirror intentionally selective. Mirroring the whole packaged
# tree previously pulled in junk artifacts and caused UI regressions.
RUNTIME_ITEMS=(
  .env
  .env.development
  .env.staging
  compat
  wg
  wg-quick
  wg_report.sh
  wi-fiman-desktop-bin
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

# If the state file already points at the runtime copy from a prior run, break
# that link before reseeding so repeated launches stay idempotent.
if [[ -L "$STATE_ROOT/service.json" ]]; then
  target=$(readlink -f "$STATE_ROOT/service.json" || true)
  runtime_service=$(readlink -f "$RUNTIME_ROOT/service.json" 2>/dev/null || true)
  if [[ -n "$target" && "$target" == "$runtime_service" ]]; then
    rm -f "$STATE_ROOT/service.json"
  fi
fi

if [[ ! -s "$STATE_ROOT/service.json" ]]; then
  printf '{}\n' > "$STATE_ROOT/service.json"
fi

shopt -s dotglob nullglob
# Clean stale runtime entries on each launch so old packaged artifacts do not
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
# already match.
if [[ ! -e "$RUNTIME_ROOT/service.json" ]] || ! cmp -s "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"; then
  cp -f "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"
fi
ln -sfn "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
rm -f "$STATE_ROOT/service.json.tmp"

export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wi-fiman-desktop-bin" "$@"
