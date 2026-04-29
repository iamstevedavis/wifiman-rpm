#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}
STATE_ROOT=${STATE_ROOT:-/var/lib/wifiman-desktop}
RUNTIME_ROOT="$STATE_ROOT/app-root"

mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT"

if [[ ! -s "$STATE_ROOT/service.json" ]]; then
  printf '{}\n' > "$STATE_ROOT/service.json"
fi

shopt -s dotglob nullglob
for src in "$APP_ROOT"/*; do
  name=${src##*/}
  if [[ "$name" == "service.json" || "$name" == "service.json.tmp" ]]; then
    continue
  fi
  ln -sfn "$src" "$RUNTIME_ROOT/$name"
done

cp -f "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"
ln -sfn "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
rm -f "$STATE_ROOT/service.json.tmp"

export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wifiman-desktopd" "$@"
