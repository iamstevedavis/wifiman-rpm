#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
export LD_LIBRARY_PATH="$APP_ROOT/compat/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_EXEC_PATH="$APP_ROOT/compat/libexec/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

exec "$APP_ROOT/upstream/usr/bin/wi-fiman-desktop" "$@"
