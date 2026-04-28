#!/usr/bin/bash
set -euo pipefail

APP_ROOT=/usr/lib/wi-fiman-desktop
STATE_ROOT=/var/lib/wifiman-desktop
mkdir -p "$STATE_ROOT"

if [[ ! -s "$APP_ROOT/service.json" ]]; then
  printf '{}\n' > "$APP_ROOT/service.json"
fi

export WEBKIT_FORCE_SANDBOX=0
export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

exec "$APP_ROOT/wi-fiman-desktop-bin" "$@"
