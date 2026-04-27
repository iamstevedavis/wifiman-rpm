#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}

docker run --rm -i \
  -v "$STAGE_DIR:/stage:ro" \
  fedora:latest bash <<'EOF'
set -euo pipefail

dnf -qy install \
  glibc \
  libstdc++ \
  gtk3 \
  gdk-pixbuf2 \
  nss \
  nspr \
  libX11 \
  libXcomposite \
  libXcursor \
  libXdamage \
  libXext \
  libXfixes \
  libXi \
  libXrandr \
  libXtst \
  libdrm \
  mesa-libgbm \
  mesa-libEGL \
  libglvnd-egl \
  pango \
  cairo \
  at-spi2-core \
  libappindicator-gtk3 \
  >/dev/null

echo "== host egl =="
rpm -q mesa-libEGL libglvnd-egl || true
echo

echo "== app ldd =="
LD_LIBRARY_PATH=/stage/compat/lib64 ldd /stage/upstream/usr/bin/wi-fiman-desktop || true
echo

echo "== daemon ldd =="
LD_LIBRARY_PATH=/stage/compat/lib64 ldd /stage/upstream/usr/lib/wi-fiman-desktop/wifiman-desktopd || true
echo

echo "== unresolved =="
LD_LIBRARY_PATH=/stage/compat/lib64 ldd /stage/upstream/usr/bin/wi-fiman-desktop | awk '/=> not found/ {print $1}' | sort -u || true
EOF

