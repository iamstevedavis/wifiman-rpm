#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=${VERSION:-1.3.0}
RELEASE=${RELEASE:-1}
TOPDIR=${TOPDIR:-"$ROOT_DIR/.rpmbuild"}
STAGE_DIR=${STAGE_DIR:-"$ROOT_DIR/out/wifiman-desktop-fedora-newer"}
TARBALL="$TOPDIR/SOURCES/wifiman-desktop-${VERSION}-stage.tar.gz"
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"
FEDORA_IMAGE=${FEDORA_IMAGE:-fedora:44}
RESTAGE=${RESTAGE:-1}

command -v docker >/dev/null

# Always run the local regression suite before staging/building a new RPM.
"$ROOT_DIR/tests/run-all.sh"

mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

if [[ "$RESTAGE" == "1" ]]; then
  rm -rf "$STAGE_DIR"
  "$ROOT_DIR/scripts/stage-wifiman-fedora-newer.sh" "$STAGE_DIR"
fi

required_paths=(
  "$STAGE_DIR/bin/wi-fiman-desktop"
)

found_ui=0
for candidate in "$STAGE_DIR/upstream/usr/bin/wifiman-desktop" \
                 "$STAGE_DIR/upstream/usr/bin/wi-fiman-desktop"; do
  if [[ -e "$candidate" ]]; then
    required_paths+=("$candidate")
    found_ui=1
    break
  fi
done
if [[ $found_ui -eq 0 ]]; then
  echo "missing staged UI binary under $STAGE_DIR/upstream/usr/bin" >&2
  echo "rebuild with: RESTAGE=1 ./scripts/build-rpm-from-stage.sh" >&2
  exit 1
fi

found_libdir=0
for candidate in "$STAGE_DIR/upstream/usr/lib/wifiman-desktop" \
                 "$STAGE_DIR/upstream/usr/lib/wi-fiman-desktop"; do
  if [[ -e "$candidate" ]]; then
    required_paths+=("$candidate")
    found_libdir=1
    break
  fi
done
if [[ $found_libdir -eq 0 ]]; then
  echo "missing staged app library directory under $STAGE_DIR/upstream/usr/lib" >&2
  echo "rebuild with: RESTAGE=1 ./scripts/build-rpm-from-stage.sh" >&2
  exit 1
fi

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
cp "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/default-service.json" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/wifiman-runtime.sh" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/scripts/wifiman-desktop.desktop" "$TOPDIR/SOURCES/"

(
  cd /
  docker run --rm \
    --workdir /rpmbuild \
    -v "$TOPDIR:/rpmbuild:Z" \
    -e VERSION="$VERSION" \
    -e RELEASE="$RELEASE" \
    "$FEDORA_IMAGE" bash -lc '
      set -euo pipefail
      dnf -qy install rpm-build desktop-file-utils systemd-rpm-macros >/dev/null
      rpmbuild \
        --define "_topdir /rpmbuild" \
        --define "app_version ${VERSION}" \
        --define "app_release ${RELEASE}" \
        -ba "/rpmbuild/SPECS/wifiman-desktop.spec"
    '
)

echo
artifacts=$(find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -type f | sort)
if [[ -z "$artifacts" ]]; then
  echo "RPM build completed without producing artifacts under $TOPDIR" >&2
  exit 1
fi
printf '%s\n' "$artifacts"
