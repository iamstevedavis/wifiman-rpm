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

# In the RPM the launcher lives in /usr/bin, separate from the helper.
runtime_helper="$(dirname -- "${BASH_SOURCE[0]}")/wifiman-runtime.sh"
if [[ ! -f "$runtime_helper" ]]; then
  runtime_helper="$APP_ROOT/wifiman-runtime.sh"
fi
RUNTIME_EXTRA_ITEMS=(wi-fiman-desktop-bin)
source "$runtime_helper"

# Match the staged wrapper's compatibility-runtime exports. The upstream
# binary still needs the bundled WebKitGTK 4.0 / libsoup2 stack, so point
# the loader and WebKit helper lookup at the mirrored compat tree.
# WEBKIT_FORCE_SANDBOX is deliberately not copied from the staged wrapper;
# sandbox settings get their own review.
export LD_LIBRARY_PATH="$RUNTIME_ROOT/compat/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$RUNTIME_ROOT/compat/libexec/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$RUNTIME_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wi-fiman-desktop-bin" "$@"
