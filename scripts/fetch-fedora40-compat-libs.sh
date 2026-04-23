#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=${1:-"$ROOT_DIR/.cache/fedora40-compat"}

mkdir -p "$WORK_DIR"

docker run --rm -v "$WORK_DIR:/out" fedora:40 bash -lc '
  set -euo pipefail
  dnf -qy install dnf-plugins-core cpio rpm-build >/dev/null
  dnf -qy install "dnf-command(download)" >/dev/null
  cd /out
  dnf download --arch x86_64 \
    webkit2gtk4.0 \
    javascriptcoregtk4.0 \
    libsoup \
    libicu \
    libxslt \
    woff2 \
    gstreamer1 \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-free-libs \
    libjxl \
    libavif \
    harfbuzz \
    harfbuzz-icu \
    enchant2 \
    libsecret \
    hyphen \
    libwayland-server \
    libmanette \
    libatomic \
    libevdev \
    libgudev \
    rav1e-libs \
    libwebp \
    elfutils-libs \
    libunwind \
    mesa-libEGL \
    orc \
    >/dev/null

  rm -rf extract && mkdir -p extract
  for rpm in *.rpm; do
    rpm2cpio "$rpm" | (cd extract && cpio -idmu) >/dev/null 2>&1
  done
'

echo "$WORK_DIR/extract/usr/lib64"
