#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SPEC_FILE="$ROOT_DIR/wifiman-desktop.spec"
STAGE_SCRIPT="$ROOT_DIR/scripts/stage-wifiman-fedora-newer.sh"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-rpm-from-stage.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"

# Upstream 1.3.0 is the packaged default everywhere it is declared.
grep -q '^%global app_version %{?app_version}%{!?app_version:1.3.0}$' "$SPEC_FILE"
grep -q '^UPSTREAM_VERSION=${UPSTREAM_VERSION:-1.3.0}$' "$STAGE_SCRIPT"
grep -q '^VERSION=${VERSION:-1.3.0}$' "$BUILD_SCRIPT"
grep -q '^FEDORA_IMAGE=${FEDORA_IMAGE:-fedora:44}$' "$BUILD_SCRIPT"
grep -q '^DEFAULT_VERSION=1.3.0$' "$ROOT_DIR/scripts/release-version.sh"
grep -q "default: '1.3.0'" "$WORKFLOW"

# 1.3.0 links against the host WebKitGTK 4.1 stack.
grep -q '^Requires:       webkit2gtk4.1$' "$SPEC_FILE"
grep -q 'libayatana-appindicator3.so.1()(64bit) or libappindicator3.so.1()(64bit)' "$SPEC_FILE"
grep -q '^Requires:       net-tools$' "$SPEC_FILE"
grep -q '^Requires:       iw$' "$SPEC_FILE"

# The private compatibility runtime was removed.
test ! -e "$ROOT_DIR/scripts/fetch-fedora40-compat-libs.sh"
assert_absent() {
  local pattern=$1
  local file=$2
  if grep -q -- "$pattern" "$file"; then
    echo "unexpected removed-compat reference: $pattern in $file" >&2
    exit 1
  fi
}
assert_absent 'fetch-fedora40-compat-libs.sh' "$STAGE_SCRIPT"
assert_absent 'UPDATER_DELAY=31536000000' "$STAGE_SCRIPT"
assert_absent 'compat/lib64' "$STAGE_SCRIPT"
assert_absent 'compat/libexec' "$STAGE_SCRIPT"
assert_absent '^  compat$' "$ROOT_DIR/scripts/wifiman-runtime.sh"
assert_absent 'compat/lib64' "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
assert_absent 'staged/compat' "$SPEC_FILE"
assert_absent '%{_prefix}/lib/wi-fiman-desktop/compat' "$SPEC_FILE"
assert_absent 'webkit2gtk-4.0' "$SPEC_FILE"

# Verification still covers the runtime pieces the MTU patch depends on.
grep -q 'libwebkit2gtk-4.1.so.0' "$ROOT_DIR/scripts/verify-fedora-newer-stage.sh"
grep -qF 'cmd ip link set mtu $(( mtu - 80 ))' "$ROOT_DIR/scripts/verify-fedora-newer-stage.sh"

echo "upstream 1.3.0 layout test passed"
