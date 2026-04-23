#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}

APP_BIN="$STAGE_DIR/upstream/usr/bin/wi-fiman-desktop"
APP_DAEMON="$STAGE_DIR/upstream/usr/lib/wi-fiman-desktop/wifiman-desktopd"
COMPAT_DIR="$STAGE_DIR/compat/lib64"

if [[ ! -x "$APP_BIN" ]]; then
  echo "missing app binary: $APP_BIN" >&2
  exit 1
fi

if [[ ! -d "$COMPAT_DIR" ]]; then
  echo "missing compat dir: $COMPAT_DIR" >&2
  exit 1
fi

echo "== stage =="
echo "$STAGE_DIR"
echo

echo "== compat payload count =="
find "$COMPAT_DIR" -maxdepth 1 \( -type f -o -type l \) | wc -l
echo

echo "== compat payload files =="
find "$COMPAT_DIR" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' | sort
echo

run_ldd() {
  local target=$1
  echo "== ldd: $target =="
  LD_LIBRARY_PATH="$COMPAT_DIR" ldd "$target" || true
  echo
}

run_ldd "$APP_BIN"

if [[ -x "$APP_DAEMON" ]]; then
  run_ldd "$APP_DAEMON"
fi

echo "== unresolved with compat dir =="
{
  LD_LIBRARY_PATH="$COMPAT_DIR" ldd "$APP_BIN" || true
  if [[ -x "$APP_DAEMON" ]]; then
    LD_LIBRARY_PATH="$COMPAT_DIR" ldd "$APP_DAEMON" || true
  fi
} | awk '/=> not found/ {print $1}' | sort -u

