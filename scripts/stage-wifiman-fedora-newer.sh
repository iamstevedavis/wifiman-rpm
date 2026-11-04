#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}
UPSTREAM_VERSION=${UPSTREAM_VERSION:-1.3.0}
UPSTREAM_URL=${UPSTREAM_URL:-"https://desktop.ea.wifiman.com/wifiman-desktop-${UPSTREAM_VERSION}-amd64.deb"}
ARCH=${ARCH:-x86_64}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$STAGE_DIR"

if [[ "$ARCH" != "x86_64" ]]; then
  echo "unsupported ARCH: $ARCH (only x86_64 is currently supported)" >&2
  exit 1
fi

curl -fsSLo "$TMP_DIR/wifiman.deb" -A 'Mozilla/5.0' "$UPSTREAM_URL"

pushd "$TMP_DIR" >/dev/null
ar x wifiman.deb
tar xzf data.tar.gz
popd >/dev/null

# Upstream 1.3.0 moved to the system WebKitGTK 4.1 / libsoup3 stack, so there
# is no app-private compatibility runtime to stage any more.
rm -rf "$STAGE_DIR/upstream" "$STAGE_DIR/bin" "$STAGE_DIR/compat"
mkdir -p "$STAGE_DIR/upstream" "$STAGE_DIR/bin"

cp -R "$TMP_DIR/usr" "$STAGE_DIR/upstream/"
install -m 0755 "$ROOT_DIR/scripts/wi-fiman-desktop-wrapper.sh" "$STAGE_DIR/bin/wi-fiman-desktop"

UPSTREAM_APP_DIR=
for candidate in \
  "$STAGE_DIR/upstream/usr/lib/wifiman-desktop" \
  "$STAGE_DIR/upstream/usr/lib/wi-fiman-desktop"
do
  if [[ -d "$candidate" ]]; then
    UPSTREAM_APP_DIR="$candidate"
    break
  fi
done

if [[ -z "$UPSTREAM_APP_DIR" ]]; then
  echo "could not find upstream app dir under $STAGE_DIR/upstream/usr/lib" >&2
  exit 1
fi

UPSTREAM_BIN=
for candidate in \
  "$STAGE_DIR/upstream/usr/bin/wifiman-desktop" \
  "$STAGE_DIR/upstream/usr/bin/wi-fiman-desktop"
do
  if [[ -f "$candidate" ]]; then
    UPSTREAM_BIN="$candidate"
    break
  fi
done

if [[ -z "$UPSTREAM_BIN" ]]; then
  echo "could not find upstream UI binary under $STAGE_DIR/upstream/usr/bin" >&2
  exit 1
fi

cat > "$STAGE_DIR/README.txt" <<EOF
Staged WiFiman Desktop for newer Fedora.

Upstream version: $UPSTREAM_VERSION
Architecture: $ARCH
Source URL: $UPSTREAM_URL

Run:
  ./bin/wi-fiman-desktop

The UI binary links against the host WebKitGTK 4.1 / libsoup3 stack.
Install these runtime packages on Fedora:

  webkit2gtk4.1 gtk3 libappindicator-gtk3 net-tools iw wireguard-tools
EOF

echo "Staged at: $STAGE_DIR"
