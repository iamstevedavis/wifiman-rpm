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
RESTAGE=${RESTAGE:-1}

command -v docker >/dev/null

mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

if [[ "$RESTAGE" == "1" ]]; then
  rm -rf "$STAGE_DIR"
  "$ROOT_DIR/scripts/stage-wifiman-1.1.2-fedora-newer.sh" "$STAGE_DIR"
fi

required_paths=(
  "$STAGE_DIR/bin/wi-fiman-desktop"
  "$STAGE_DIR/compat/lib64"
  "$STAGE_DIR/compat/libexec/webkit2gtk-4.0/WebKitNetworkProcess"
  "$STAGE_DIR/compat/libexec/webkit2gtk-4.0/WebKitWebProcess"
  "$STAGE_DIR/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "missing staged artifact: $path" >&2
    echo "rebuild with: RESTAGE=1 ./scripts/build-rpm-from-stage.sh" >&2
    exit 1
  fi
done

rm -f "$TARBALL"
tar -C "$STAGE_DIR" -czf "$TARBALL" .
cp "$SPEC_FILE" "$TOPDIR/SPECS/"
cp "$ROOT_DIR/LICENSE" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/wi-fiman-desktop-launcher.sh" "$TOPDIR/SOURCES/"

docker run --rm \
  --workdir /rpmbuild \
  -v "$TOPDIR:/rpmbuild:Z" \
  "$FEDORA_IMAGE" bash -lc '
    set -euo pipefail
    dnf -qy install rpm-build desktop-file-utils systemd-rpm-macros >/dev/null
    rpmbuild \
      --define "_topdir /rpmbuild" \
      -ba "/rpmbuild/SPECS/wifiman-desktop.spec"
  '

echo
artifacts=$(find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -type f | sort)
if [[ -z "$artifacts" ]]; then
  echo "RPM build completed without producing artifacts under $TOPDIR" >&2
  exit 1
fi
printf '%s\n' "$artifacts"
