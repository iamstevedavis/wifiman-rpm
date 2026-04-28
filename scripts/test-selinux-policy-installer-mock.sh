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
module_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -M) module_name=$2; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$module_name.te" <<EOT
module $module_name 1.0;
require { type init_t; class tcp_socket name_connect; }
allow init_t self:tcp_socket name_connect;
EOT
: > "$module_name.mod"
: > "$module_name.pp"
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
grep -q 'audit2allow -M wifiman_desktop_local' "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/wifiman_desktop_local.pp' "$LOG_FILE"
grep -q 'systemctl restart wifiman-desktop.service' "$LOG_FILE"
grep -q 'Installed SELinux base module: wifiman-desktop' "$WORK_DIR/out.txt"

echo "SELinux policy installer mock test passed"
