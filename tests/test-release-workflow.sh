#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-rpm-from-stage.sh"
README="$ROOT_DIR/README.md"

test -f "$WORKFLOW"
bash -n "$BUILD_SCRIPT"

grep -q "upstream_version:" "$WORKFLOW"
grep -q "rpm_release:" "$WORKFLOW"
grep -q "create_release:" "$WORKFLOW"
grep -q 'Validate semantic version' "$WORKFLOW"
grep -q 'VERSION="${VERSION}" RELEASE="${RELEASE}" UPSTREAM_VERSION="${UPSTREAM_VERSION}" ./scripts/build-rpm-from-stage.sh' "$WORKFLOW"
grep -q -- '--define "app_version ${VERSION}"' "$BUILD_SCRIPT"
grep -q -- '--define "app_release ${RELEASE}"' "$BUILD_SCRIPT"
grep -q 'ASSET_PREFIX=wifiman-desktop-${VERSION}-${RELEASE}' "$WORKFLOW"
grep -q 'sha256sum \* > "${ASSET_PREFIX}-SHA256SUMS.txt"' "$WORKFLOW"
grep -q 'Built from upstream WiFiman Desktop' "$WORKFLOW"
grep -q 'sudo dnf install ./\${rpm_name}' "$WORKFLOW"
grep -q 'body_path: release-notes.md' "$WORKFLOW"
grep -q 'tag_name: ${{ env.RELEASE_TAG }}' "$WORKFLOW"
grep -q 'fail_on_unmatched_files: true' "$WORKFLOW"
grep -q 'semantic-version tag like `v1.2.10`' "$README"
grep -q 'Release notes include the upstream WiFiman Desktop version and RPM install commands.' "$README"

echo 'release workflow test passed'
