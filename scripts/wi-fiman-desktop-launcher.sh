#!/usr/bin/bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}
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

mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT"

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
for src in "$APP_ROOT"/*; do
  name=${src##*/}
  if [[ "$name" == "service.json" || "$name" == "service.json.tmp" ]]; then
    continue
  fi
  ln -sfn "$src" "$RUNTIME_ROOT/$name"
done

if [[ ! -e "$RUNTIME_ROOT/service.json" ]] || ! cmp -s "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"; then
  cp -f "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"
fi
ln -sfn "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
rm -f "$STATE_ROOT/service.json.tmp"

export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wi-fiman-desktop-bin" "$@"
