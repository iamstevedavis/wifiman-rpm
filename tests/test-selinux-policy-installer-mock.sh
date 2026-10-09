#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-selinux-policy.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="$WORK_DIR/bin"
LOG_FILE="$WORK_DIR/tool.log"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/checkmodule" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'checkmodule %s\n' "$*" >> "$TEST_LOG"
out=""
in=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) in=$1; shift ;;
  esac
done
: > "$out"
EOF

cat > "$BIN_DIR/semodule_package" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'semodule_package %s\n' "$*" >> "$TEST_LOG"
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) shift ;;
  esac
done
: > "$out"
EOF

cat > "$BIN_DIR/semodule" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'semodule %s\n' "$*" >> "$TEST_LOG"
EOF

cat > "$BIN_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >> "$TEST_LOG"
EOF

cat > "$BIN_DIR/ausearch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ausearch %s\n' "$*" >> "$TEST_LOG"
if [[ ${TEST_NO_AVCS:-0} == 1 ]]; then exit 1; fi
if printf '%s\n' "$*" | grep -q -- '--raw'; then
  printf 'fake avc raw\n'
  exit 0
fi
exit 0
EOF

cat > "$BIN_DIR/audit2allow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'audit2allow %s\n' "$*" >> "$TEST_LOG"
if [[ ${TEST_GENERATION_FAIL:-0} == 1 ]]; then
  echo 'generation failed' >&2
  exit 1
fi
module_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) module_name=$2; shift 2 ;;
    *) shift ;;
  esac
done
cat <<EOT
module $module_name 1.0;
require { type init_t; class tcp_socket name_connect; }
allow init_t self:tcp_socket name_connect;
EOT
EOF

# Keep persistent review artifacts inside the test fixture.
cat > "$BIN_DIR/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${2:-} == /var/tmp/wifiman-selinux-review.XXXXXX ]]; then
  exec /usr/bin/mktemp -d "$HOME/review.XXXXXX"
fi
exec /usr/bin/mktemp "$@"
EOF

chmod +x "$BIN_DIR"/*

if ! TEST_LOG="$LOG_FILE" \
PATH="$BIN_DIR:$PATH" \
HOME="$WORK_DIR" \
WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 \
bash "$INSTALLER" > "$WORK_DIR/out.txt" 2>&1; then
  cat "$WORK_DIR/out.txt" >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi

# Assertions on mocked behavior
grep -q 'checkmodule .*wifiman-desktop.te' "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/wifiman-desktop.pp' "$LOG_FILE"
grep -q 'audit2allow -m wifiman_desktop_local' "$LOG_FILE"
if grep -q 'semodule .*wifiman_desktop_local.pp' "$LOG_FILE"; then
  echo 'unreviewed AVC module must not be installed' >&2
  exit 1
fi
grep -q 'systemctl restart wifiman-desktop.service' "$LOG_FILE"
grep -q 'Installed SELinux base module: wifiman-desktop' "$WORK_DIR/out.txt"
grep -q 'NOT installed' "$WORK_DIR/out.txt"
grep -q 'shared init_t' "$WORK_DIR/out.txt"
reviewed_source=$(find "$WORK_DIR" -path '*/review.*/wifiman_desktop_local.te')
[[ -s "$reviewed_source" ]]
[[ -s "${reviewed_source%/*}/avc.log" ]]
[[ $(stat -c %a "${reviewed_source%/*}") == 700 ]]

# Explicitly reviewed source is compiled afresh; no audit generation runs.
: > "$LOG_FILE"
TEST_LOG="$LOG_FILE" PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
  WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 REVIEWED_AVC_TE="$reviewed_source" \
  bash "$INSTALLER" > "$WORK_DIR/reviewed.out" 2>&1
grep -q 'checkmodule .*wifiman_desktop_local.te' "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/wifiman_desktop_local.pp' "$LOG_FILE"
grep -q 'allow init_t self:tcp_socket name_connect;' "$WORK_DIR/reviewed.out"
if grep -Eq '^(ausearch|audit2allow) ' "$LOG_FILE"; then exit 1; fi

# Missing review sources fail before installing any module.
: > "$LOG_FILE"
if TEST_LOG="$LOG_FILE" PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
  WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 REVIEWED_AVC_TE="$WORK_DIR/missing.te" \
  bash "$INSTALLER" > "$WORK_DIR/missing.out" 2>&1; then exit 1; fi
grep -q 'Missing or empty reviewed policy source' "$WORK_DIR/missing.out"
[[ ! -s "$LOG_FILE" ]]

# A policy generation failure is visible and prevents reporting success.
: > "$LOG_FILE"
if TEST_LOG="$LOG_FILE" PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
  WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 TEST_GENERATION_FAIL=1 \
  bash "$INSTALLER" > "$WORK_DIR/fail.out" 2>&1; then exit 1; fi
grep -q 'generation failed' "$WORK_DIR/fail.out"
if grep -q 'semodule .*wifiman_desktop_local.pp' "$LOG_FILE"; then exit 1; fi

# No AVCs means base policy only, with no generated artifact.
: > "$LOG_FILE"
TEST_LOG="$LOG_FILE" PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
  WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 TEST_NO_AVCS=1 \
  bash "$INSTALLER" > "$WORK_DIR/no-avcs.out" 2>&1
grep -q 'No SELinux AVC denials found' "$WORK_DIR/no-avcs.out"
if grep -q '^audit2allow ' "$LOG_FILE"; then exit 1; fi

echo "SELinux policy installer mock test passed"
