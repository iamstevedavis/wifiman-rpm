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

# Upstream 1.3.0 links against the host WebKitGTK 4.1 / libsoup3 stack, so no
# loader or WebKit helper overrides are needed any more.

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wi-fiman-desktop-bin" "$@"
