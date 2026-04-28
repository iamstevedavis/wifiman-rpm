#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}
UPSTREAM_VERSION=${UPSTREAM_VERSION:-1.2.10}
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

rm -rf "$STAGE_DIR/upstream" "$STAGE_DIR/bin" "$STAGE_DIR/compat"
mkdir -p "$STAGE_DIR/upstream" "$STAGE_DIR/bin" "$STAGE_DIR/compat/lib64"

cp -R "$TMP_DIR/usr" "$STAGE_DIR/upstream/"
install -m 0755 "$ROOT_DIR/scripts/wi-fiman-desktop-wrapper.sh" "$STAGE_DIR/bin/wi-fiman-desktop"

EXTRACT_ROOT=$("$ROOT_DIR/scripts/fetch-fedora40-compat-libs.sh")
EXTRACT_LIB64="$EXTRACT_ROOT/usr/lib64"

patterns=(
  'libwebkit2gtk-4.0.so*'
  'libjavascriptcoregtk-4.0.so*'
  'libsoup-2.4.so*'
  'libicui18n.so*'
  'libicuuc.so*'
  'libicudata.so*'
  'libxslt.so*'
  'libexslt.so*'
  'libwoff2dec.so*'
  'libwoff2common.so*'
  'libgsttranscoder-1.0.so*'
  'libjxl.so*'
  'libjxl_threads.so*'
  'libavif.so*'
  'libharfbuzz-icu.so*'
  'libenchant-2.so*'
  'libsecret-1.so*'
  'libhyphen.so*'
  'libwayland-server.so*'
  'libmanette-0.2.so*'
  'libatomic.so*'
  'libgstallocators-1.0.so*'
  'libgstapp-1.0.so*'
  'libgstbase-1.0.so*'
  'libgstreamer-1.0.so*'
  'libgstpbutils-1.0.so*'
  'libgstaudio-1.0.so*'
  'libgsttag-1.0.so*'
  'libgstvideo-1.0.so*'
  'libgstgl-1.0.so*'
  'libgstfft-1.0.so*'
  'libwebpdemux.so*'
  'librav1e.so*'
  'libSvtAv1Enc.so*'
  'libevdev.so*'
  'libgudev-1.0.so*'
  'libdw.so*'
  'liborc-0.4.so*'
  'libunwind.so*'
  'libcpuinfo.so*'
)

shopt -s nullglob
for pattern in "${patterns[@]}"; do
  for f in "$EXTRACT_LIB64"/$pattern; do
    cp -aL "$f" "$STAGE_DIR/compat/lib64/"
  done
done

mkdir -p \
  "$STAGE_DIR/compat/libexec/webkit2gtk-4.0" \
  "$STAGE_DIR/compat/lib64/webkit2gtk-4.0/injected-bundle"

cp -aL "$EXTRACT_ROOT/usr/libexec/webkit2gtk-4.0/WebKitNetworkProcess" \
  "$STAGE_DIR/compat/libexec/webkit2gtk-4.0/"
cp -aL "$EXTRACT_ROOT/usr/libexec/webkit2gtk-4.0/WebKitWebProcess" \
  "$STAGE_DIR/compat/libexec/webkit2gtk-4.0/"
cp -aL "$EXTRACT_ROOT/usr/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so" \
  "$STAGE_DIR/compat/lib64/webkit2gtk-4.0/injected-bundle/"

cat > "$STAGE_DIR/README.txt" <<EOF
Staged WiFiman Desktop for newer Fedora.

Upstream version: $UPSTREAM_VERSION
Architecture: $ARCH
Source URL: $UPSTREAM_URL

Run:
  ./bin/wi-fiman-desktop

This wrapper uses a private compatibility runtime under:
  ./compat/lib64

Note:
  EGL/GLVND/mesa GL stack pieces are expected to be provided by the host Fedora system.
EOF

echo "Staged at: $STAGE_DIR"
