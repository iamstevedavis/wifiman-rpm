#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR="$ROOT_DIR/tests"

tests=(
  "$TEST_DIR/test-daemon-wrapper-rerun.sh"
  "$TEST_DIR/test-desktop-entry.sh"
  "$TEST_DIR/test-dnf-cache-refresh.sh"
  "$TEST_DIR/test-internal-path-contract.sh"
  "$TEST_DIR/test-launcher-xdg-state-home.sh"
  "$TEST_DIR/test-launcher-state-root.sh"
  "$TEST_DIR/test-launcher-system-runtime.sh"
  "$TEST_DIR/test-launcher-installed-rpm-smoke.sh"
  "$TEST_DIR/test-launcher-service-persistence.sh"
  "$TEST_DIR/test-daemon-service-persistence.sh"
  "$TEST_DIR/test-shared-runtime-setup.sh"
  "$TEST_DIR/test-runtime-mirror-cleanup.sh"
  "$TEST_DIR/test-runtime-wrapper.sh"
  "$TEST_DIR/test-wg-quick-mtu-cap.sh"
  "$TEST_DIR/test-release-workflow.sh"
  "$TEST_DIR/test-release-version.sh"
  "$TEST_DIR/test-workflow-yaml.sh"
  "$TEST_DIR/test-selinux-policy-installer.sh"
  "$TEST_DIR/test-selinux-policy-installer-mock.sh"
  "$TEST_DIR/test-selinux-install-remove-roundtrip.sh"
  "$TEST_DIR/test-script-syntax.sh"
  "$TEST_DIR/test-spec-log-symlink.sh"
  "$TEST_DIR/test-spec-net-tools.sh"
  "$TEST_DIR/test-upstream-1.3.sh"
)

for test_script in "${tests[@]}"; do
  echo "==> $(basename "$test_script")"
  "$test_script"
  echo
done

echo "All tests passed"
