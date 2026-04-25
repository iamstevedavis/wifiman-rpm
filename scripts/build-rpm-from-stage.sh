#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=${VERSION:-1.1.2}
RELEASE=${RELEASE:-1}
TOPDIR=${TOPDIR:-"$ROOT_DIR/.rpmbuild"}
STAGE_DIR=${STAGE_DIR:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}
TARBALL="$TOPDIR/SOURCES/wifiman-desktop-${VERSION}-stage.tar.gz"
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"
FEDORA_IMAGE=${FEDORA_IMAGE:-fedora:40}

command -v docker >/dev/null

mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

if [[ ! -x "$STAGE_DIR/bin/wi-fiman-desktop" ]]; then
  "$ROOT_DIR/scripts/stage-wifiman-1.1.2-fedora-newer.sh" "$STAGE_DIR"
fi

tar -C "$STAGE_DIR" -czf "$TARBALL" .
cp "$SPEC_FILE" "$TOPDIR/SPECS/"
cp "$ROOT_DIR/LICENSE" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/wi-fiman-desktop-launcher.sh" "$TOPDIR/SOURCES/"

docker run --rm \
  -v "$TOPDIR:/rpmbuild" \
  "$FEDORA_IMAGE" bash -lc '
    set -euo pipefail
    dnf -qy install rpm-build desktop-file-utils systemd-rpm-macros >/dev/null
    rpmbuild \
      --define "_topdir /rpmbuild" \
      -ba "/rpmbuild/SPECS/wifiman-desktop.spec"
  '

echo
find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -type f | sort
