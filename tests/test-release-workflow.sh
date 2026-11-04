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
grep -q 'overwrite:' "$WORKFLOW"
grep -qF './scripts/release-version.sh | tee -a "$GITHUB_ENV"' "$WORKFLOW"
grep -q 'Refuse to replace an existing release' "$WORKFLOW"
grep -qF 'git ls-remote --exit-code --tags origin "refs/tags/${RELEASE_TAG}"' "$WORKFLOW"
grep -qF 'target_commitish: ${{ github.sha }}' "$WORKFLOW"
# upstream_version must not default to a fixed version, or bumping only
# `version` would silently package the old upstream.
if awk '/upstream_version:/{f=1} f&&/default:/{print; exit}' "$WORKFLOW" | grep -q "[0-9]"; then
  echo "upstream_version input must default to empty" >&2
  exit 1
fi
# Version/tag handling must go through the tested script, not inline shell.
if grep -q 'GITHUB_REF_NAME#v' "$WORKFLOW"; then
  echo "release.yml must use scripts/release-version.sh for tag parsing" >&2
  exit 1
fi

TEST_WORKFLOW="$ROOT_DIR/.github/workflows/test.yml"
test -f "$TEST_WORKFLOW"
grep -q 'pull_request:' "$TEST_WORKFLOW"
grep -qF 'run: ./tests/run-all.sh' "$TEST_WORKFLOW"
grep -q 'VERSION="${VERSION}" RELEASE="${RELEASE}" UPSTREAM_VERSION="${UPSTREAM_VERSION}" ./scripts/build-rpm-from-stage.sh' "$WORKFLOW"
grep -q -- '--define "app_version ${VERSION}"' "$BUILD_SCRIPT"
grep -q -- '--define "app_release ${RELEASE}"' "$BUILD_SCRIPT"
grep -qF 'ASSET_PREFIX=wifiman-desktop-%s-%s' "$ROOT_DIR/scripts/release-version.sh"
grep -q 'sha256sum \* > "${ASSET_PREFIX}-SHA256SUMS.txt"' "$WORKFLOW"
grep -q 'Built from upstream WiFiman Desktop' "$WORKFLOW"
grep -Fq 'The private app root remains \`/usr/lib/wi-fiman-desktop\` for compatibility' "$WORKFLOW"
grep -Fq 'No internal-path migration or clean reinstall is required.' "$WORKFLOW"
grep -q 'sudo dnf install ./\${rpm_name}' "$WORKFLOW"
grep -q 'body_path: release-notes.md' "$WORKFLOW"
grep -q 'tag_name: ${{ env.RELEASE_TAG }}' "$WORKFLOW"
grep -q 'fail_on_unmatched_files: true' "$WORKFLOW"
grep -q 'semantic-version tag like `v1.2.10`' "$README"
grep -q 'Push `vX.Y.Z-N`' "$README"
grep -q 'Release notes include the upstream WiFiman Desktop version and RPM install commands.' "$README"

echo 'release workflow test passed'
