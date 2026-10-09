#!/usr/bin/env bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}
STATE_ROOT=${STATE_ROOT:-/var/lib/wifiman-desktop}
RUNTIME_ROOT="$STATE_ROOT/app-root"

# Repository scripts share a directory; the RPM also installs the helper here.
runtime_helper="$(dirname -- "${BASH_SOURCE[0]}")/wifiman-runtime.sh"
RUNTIME_EXTRA_ITEMS=()
source "$runtime_helper"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wifiman-desktopd" "$@"
