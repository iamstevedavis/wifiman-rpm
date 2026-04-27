#!/usr/bin/bash
set -euo pipefail

APP_ROOT=/usr/lib/wi-fiman-desktop
STATE_ROOT=/var/lib/wifiman-desktop
mkdir -p "$STATE_ROOT"

if [[ ! -s "$APP_ROOT/service.json" ]]; then
  printf '{}\n' > "$APP_ROOT/service.json"
fi

export LD_LIBRARY_PATH="$APP_ROOT/compat/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_EXEC_PATH="$APP_ROOT/compat/libexec/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"
export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

exec "$APP_ROOT/wi-fiman-desktop-bin" "$@"
