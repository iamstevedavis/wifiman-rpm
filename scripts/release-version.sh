#!/usr/bin/env bash
set -euo pipefail

# Resolve release versions for .github/workflows/release.yml.
#
# Tag pushes: vX.Y.Z or vX.Y.Z-N
#   VERSION=X.Y.Z, UPSTREAM_VERSION=X.Y.Z, RELEASE=N (default 1),
#   RELEASE_TAG=the pushed tag.
# Manual runs: INPUT_VERSION, INPUT_UPSTREAM_VERSION, INPUT_RPM_RELEASE
#   UPSTREAM_VERSION defaults to VERSION, RELEASE defaults to 1, and
#   RELEASE_TAG is vVERSION-RELEASE, so a packaging-only rebuild gets its own
#   release instead of replacing the vVERSION one.
#
# Prints KEY=VALUE lines suitable for appending to $GITHUB_ENV.

DEFAULT_VERSION=1.3.0
semver='^[0-9]+\.[0-9]+\.[0-9]+$'

die() {
  printf 'release-version: %s\n' "$*" >&2
  exit 1
}

ref=${GITHUB_REF:-}
ref_name=${GITHUB_REF_NAME:-}

if [[ "$ref" == refs/tags/v* ]]; then
  tag_version=${ref_name#v}
  if [[ "$tag_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-([1-9][0-9]*))?$ ]]; then
    version=${BASH_REMATCH[1]}
    release=${BASH_REMATCH[3]:-1}
  else
    die "tag must be vX.Y.Z or vX.Y.Z-N (got $ref_name)"
  fi
  upstream_version=$version
  release_tag=$ref_name
else
  version=${INPUT_VERSION:-$DEFAULT_VERSION}
  upstream_version=${INPUT_UPSTREAM_VERSION:-$version}
  release=${INPUT_RPM_RELEASE:-1}
  release_tag="v${version}-${release}"
fi

[[ "$version" =~ $semver ]] || die "version must look like 1.3.0 (got $version)"
[[ "$upstream_version" =~ $semver ]] || die "upstream_version must look like 1.3.0 (got $upstream_version)"
[[ "$release" =~ ^[1-9][0-9]*$ ]] || die "rpm_release must be a positive integer (got $release)"

printf 'VERSION=%s\n' "$version"
printf 'UPSTREAM_VERSION=%s\n' "$upstream_version"
printf 'RELEASE=%s\n' "$release"
printf 'RELEASE_TAG=%s\n' "$release_tag"
printf 'ASSET_PREFIX=wifiman-desktop-%s-%s\n' "$version" "$release"
