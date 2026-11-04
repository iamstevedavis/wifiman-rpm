#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

APP_BIN=
for candidate in \
  "$STAGE_DIR/upstream/usr/bin/wifiman-desktop" \
  "$STAGE_DIR/upstream/usr/bin/wi-fiman-desktop"
do
  if [[ -x "$candidate" ]]; then
    APP_BIN="$candidate"
    break
  fi
done

APP_LIBDIR=
for candidate in \
  "$STAGE_DIR/upstream/usr/lib/wifiman-desktop" \
  "$STAGE_DIR/upstream/usr/lib/wi-fiman-desktop"
do
  if [[ -d "$candidate" ]]; then
    APP_LIBDIR="$candidate"
    break
  fi
done

[[ -n "$APP_BIN" ]] || fail "missing app binary under $STAGE_DIR/upstream/usr/bin"
[[ -n "$APP_LIBDIR" ]] || fail "missing app lib dir under $STAGE_DIR/upstream/usr/lib"

APP_DAEMON="$APP_LIBDIR/wifiman-desktopd"
WG_QUICK="$APP_LIBDIR/wg-quick"

if [[ -d "$STAGE_DIR/compat" ]]; then
  fail "staged tree still contains a private compat runtime: $STAGE_DIR/compat"
fi

echo "== stage =="
echo "$STAGE_DIR"
echo

if [[ -n "$APP_BIN" ]]; then
  echo "== app binary =="
  echo "$APP_BIN"
  echo

  echo "== required WebKitGTK 4.1 linkage =="
  needed=$(readelf -d "$APP_BIN" | awk '/NEEDED/ {print $NF}' | tr -d '[]')
  for soname in libwebkit2gtk-4.1.so.0 libsoup-3.0.so.0 libjavascriptcoregtk-4.1.so.0; do
    if grep -qx "$soname" <<<"$needed"; then
      echo "ok: $soname"
    else
      fail "$APP_BIN does not link against $soname"
    fi
  done
  echo

  echo "== ldd: app =="
  ldd "$APP_BIN" || fail "ldd failed for $APP_BIN"
  echo
fi

if [[ -x "$APP_DAEMON" ]]; then
  echo "== ldd: daemon =="
  ldd "$APP_DAEMON" || fail "ldd failed for $APP_DAEMON"
  echo
else
  fail "missing daemon binary: $APP_DAEMON"
fi

echo "== unresolved libraries =="
unresolved=$(
  {
    [[ -n "$APP_BIN" ]] && ldd "$APP_BIN" || true
    [[ -x "$APP_DAEMON" ]] && ldd "$APP_DAEMON" || true
  } | awk -F' => ' '/=> not found/ {print $1}' | sort -u
)
if [[ -n "$unresolved" ]]; then
  printf '%s\n' "$unresolved"
  fail "unresolved shared libraries"
else
  echo "none"
fi
echo

echo "== wg-quick MTU cap target =="
if [[ -f "$WG_QUICK" ]]; then
  if grep -qF 'cmd ip link set mtu $(( mtu - 80 ))' "$WG_QUICK"; then
    grep -nF 'cmd ip link set mtu $(( mtu - 80 ))' "$WG_QUICK"
    echo "ok: runtime MTU cap can patch wg-quick"
  else
    fail "$WG_QUICK no longer contains the expected MTU line"
  fi
else
  fail "missing wg-quick: $WG_QUICK"
fi
echo

if (( failures > 0 )); then
  echo "verification failed with $failures error(s)" >&2
  exit 1
fi

echo "stage verification passed"
