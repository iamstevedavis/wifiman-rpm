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

# If the state file already points at the runtime copy from a prior run, break
# that link before reseeding so repeated service starts stay idempotent.
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
  src="$APP_ROOT/$name"
  if [[ -e "$src" ]]; then
    ln -sfn "$src" "$RUNTIME_ROOT/$name"
  fi
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
exec "$RUNTIME_ROOT/wifiman-desktopd" "$@"
