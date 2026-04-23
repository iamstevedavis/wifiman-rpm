#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}
UPSTREAM_VERSION=${UPSTREAM_VERSION:-1.1.2}
UPSTREAM_URL=${UPSTREAM_URL:-"https://desktop.ea.wifiman.com/wifiman-desktop-${UPSTREAM_VERSION}-amd64.deb"}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$STAGE_DIR"

curl -fsSLo "$TMP_DIR/wifiman.deb" -A 'Mozilla/5.0' "$UPSTREAM_URL"

pushd "$TMP_DIR" >/dev/null
ar x wifiman.deb
tar xzf data.tar.gz
popd >/dev/null

rm -rf "$STAGE_DIR/upstream" "$STAGE_DIR/bin" "$STAGE_DIR/compat"
mkdir -p "$STAGE_DIR/upstream" "$STAGE_DIR/bin" "$STAGE_DIR/compat/lib64"

cp -R "$TMP_DIR/usr" "$STAGE_DIR/upstream/"
install -m 0755 "$ROOT_DIR/scripts/wi-fiman-desktop-wrapper.sh" "$STAGE_DIR/bin/wi-fiman-desktop"

EXTRACT_DIR=$("$ROOT_DIR/scripts/fetch-fedora40-compat-libs.sh")

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
)

shopt -s nullglob
for pattern in "${patterns[@]}"; do
  for f in "$EXTRACT_DIR"/$pattern; do
    cp -aL "$f" "$STAGE_DIR/compat/lib64/"
  done
done

cat > "$STAGE_DIR/README.txt" <<'EOF'
Staged WiFiman Desktop for newer Fedora.

Run:
  ./bin/wi-fiman-desktop

This wrapper uses a private compatibility runtime under:
  ./compat/lib64
EOF

echo "Staged at: $STAGE_DIR"
