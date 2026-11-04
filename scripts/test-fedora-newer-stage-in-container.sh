#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE_DIR=${1:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}

docker run --rm -i \
  -v "$STAGE_DIR:/stage:ro" \
  -v "$ROOT_DIR/scripts:/scripts:ro" \
  fedora:latest bash <<'EOF'
set -euo pipefail

dnf -qy install \
  binutils \
  glibc \
  libstdc++ \
  gtk3 \
  webkit2gtk4.1 \
  libappindicator-gtk3 \
  net-tools \
  iw \
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
  >/dev/null

bash /scripts/verify-fedora-newer-stage.sh /stage
EOF
