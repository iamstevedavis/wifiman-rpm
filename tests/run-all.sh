#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR="$ROOT_DIR/tests"

tests=(
  "$TEST_DIR/test-launcher-state-root.sh"
  "$TEST_DIR/test-runtime-wrapper.sh"
  "$TEST_DIR/test-selinux-policy-installer.sh"
  "$TEST_DIR/test-selinux-policy-installer-mock.sh"
)

for test_script in "${tests[@]}"; do
  echo "==> $(basename "$test_script")"
  "$test_script"
  echo
done

echo "All tests passed"
