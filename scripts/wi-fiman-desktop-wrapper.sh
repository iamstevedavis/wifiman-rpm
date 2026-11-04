#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

# Upstream 1.3.0 renamed the UI binary; keep accepting the old spelling.
APP_BIN=
for candidate in \
  "$APP_ROOT/upstream/usr/bin/wifiman-desktop" \
  "$APP_ROOT/upstream/usr/bin/wi-fiman-desktop"
do
  if [[ -x "$candidate" ]]; then
    APP_BIN="$candidate"
    break
  fi
done

if [[ -z "$APP_BIN" ]]; then
  echo "could not find the WiFiman Desktop UI binary under $APP_ROOT/upstream/usr/bin" >&2
  exit 1
fi

exec "$APP_BIN" "$@"
