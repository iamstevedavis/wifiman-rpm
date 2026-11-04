#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/scripts/release-version.sh"

# Run the resolver with a clean environment plus the given assignments.
resolve() {
  env -i PATH="$PATH" "$@" bash "$SCRIPT"
}

expect() {
  local output=$1 expected=$2
  if [[ "$output" != "$expected" ]]; then
    printf 'expected:\n%s\ngot:\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}

expect_failure() {
  local message=$1
  shift
  local stderr
  if stderr=$(resolve "$@" 2>&1 >/dev/null); then
    echo "expected failure for: $*" >&2
    exit 1
  fi
  grep -q -- "$message" <<<"$stderr"
}

# --- tag push: vX.Y.Z -----------------------------------------------------
expect "$(resolve GITHUB_REF=refs/tags/v1.3.0 GITHUB_REF_NAME=v1.3.0)" \
'VERSION=1.3.0
UPSTREAM_VERSION=1.3.0
RELEASE=1
RELEASE_TAG=v1.3.0
ASSET_PREFIX=wifiman-desktop-1.3.0-1'

# --- tag push: vX.Y.Z-N sets the RPM release ------------------------------
expect "$(resolve GITHUB_REF=refs/tags/v1.2.10-2 GITHUB_REF_NAME=v1.2.10-2)" \
'VERSION=1.2.10
UPSTREAM_VERSION=1.2.10
RELEASE=2
RELEASE_TAG=v1.2.10-2
ASSET_PREFIX=wifiman-desktop-1.2.10-2'

# --- tag push: malformed tags are rejected --------------------------------
expect_failure 'tag must be vX.Y.Z or vX.Y.Z-N' GITHUB_REF=refs/tags/v1.2 GITHUB_REF_NAME=v1.2
expect_failure 'tag must be vX.Y.Z or vX.Y.Z-N' GITHUB_REF=refs/tags/v1.2.10-rc1 GITHUB_REF_NAME=v1.2.10-rc1
expect_failure 'tag must be vX.Y.Z or vX.Y.Z-N' GITHUB_REF=refs/tags/v1.2.10-0 GITHUB_REF_NAME=v1.2.10-0

# --- manual run: defaults --------------------------------------------------
expect "$(resolve GITHUB_REF=refs/heads/develop GITHUB_REF_NAME=develop)" \
'VERSION=1.3.0
UPSTREAM_VERSION=1.3.0
RELEASE=1
RELEASE_TAG=v1.3.0-1
ASSET_PREFIX=wifiman-desktop-1.3.0-1'

# --- manual run: packaging-only rebuild gets its own tag ------------------
expect "$(resolve GITHUB_REF=refs/heads/develop INPUT_VERSION=1.2.10 INPUT_RPM_RELEASE=2)" \
'VERSION=1.2.10
UPSTREAM_VERSION=1.2.10
RELEASE=2
RELEASE_TAG=v1.2.10-2
ASSET_PREFIX=wifiman-desktop-1.2.10-2'

# --- manual run: upstream version follows version unless overridden -------
resolve GITHUB_REF=refs/heads/develop INPUT_VERSION=1.3.0 | grep -qx 'UPSTREAM_VERSION=1.3.0'
resolve GITHUB_REF=refs/heads/develop INPUT_VERSION=1.3.1 INPUT_UPSTREAM_VERSION=1.3.0 \
  | grep -qx 'UPSTREAM_VERSION=1.3.0'

# --- manual run: invalid inputs are rejected ------------------------------
expect_failure 'version must look like' GITHUB_REF=refs/heads/develop INPUT_VERSION=1.3
expect_failure 'upstream_version must look like' GITHUB_REF=refs/heads/develop INPUT_UPSTREAM_VERSION=latest
expect_failure 'rpm_release must be a positive integer' GITHUB_REF=refs/heads/develop INPUT_RPM_RELEASE=0
expect_failure 'rpm_release must be a positive integer' GITHUB_REF=refs/heads/develop INPUT_RPM_RELEASE=2a

echo 'release version test passed'
