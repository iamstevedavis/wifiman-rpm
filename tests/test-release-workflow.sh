#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-rpm-from-stage.sh"

test -f "$WORKFLOW"
bash -n "$BUILD_SCRIPT"

grep -q "rpm_release:" "$WORKFLOW"
grep -q "create_release:" "$WORKFLOW"
grep -q 'VERSION="${VERSION}" RELEASE="${RELEASE}" ./scripts/build-rpm-from-stage.sh' "$WORKFLOW"
grep -q 'ASSET_PREFIX=wifiman-desktop-${VERSION}-${RELEASE}' "$WORKFLOW"
grep -q 'sha256sum \* > "${ASSET_PREFIX}-SHA256SUMS.txt"' "$WORKFLOW"
grep -q 'if-no-files-found: error' "$WORKFLOW"
grep -q 'tag_name: ${{ env.RELEASE_TAG }}' "$WORKFLOW"
grep -q 'fail_on_unmatched_files: true' "$WORKFLOW"

echo 'release workflow test passed'
