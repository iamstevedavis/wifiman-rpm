#!/usr/bin/bash
set -euo pipefail

APP_ROOT=/usr/lib/wi-fiman-desktop
export LD_LIBRARY_PATH="$APP_ROOT/compat/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_EXEC_PATH="$APP_ROOT/compat/libexec/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

exec "$APP_ROOT/wi-fiman-desktop-bin" "$@"
