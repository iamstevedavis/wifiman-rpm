#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-selinux-policy.sh"
FC_FILE="$ROOT_DIR/scripts/wifiman-desktop.fc"
LEGACY_TE="$ROOT_DIR/scripts/wifiman-desktop-legacy.te"
DEDICATED_TE="$ROOT_DIR/scripts/wifiman-desktop.te"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="$WORK_DIR/bin"
LOG_FILE="$WORK_DIR/tool.log"
APP_ROOT="$WORK_DIR/app-root"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$BIN_DIR" "$APP_ROOT" "$STATE_ROOT/app-root"
touch "$APP_ROOT/wifiman-desktopd-wrapper" "$APP_ROOT/wifiman-desktopd" \
  "$APP_ROOT/wg" "$APP_ROOT/wg-quick" "$APP_ROOT/wg_report.sh" \
  "$APP_ROOT/wireguard-go" "$APP_ROOT/service.json"
touch "$STATE_ROOT/service.json" "$STATE_ROOT/wifiman-desktop.log" \
  "$STATE_ROOT/app-root/service.json" "$STATE_ROOT/app-root/wifiman-desktop.log"
: > "$LOG_FILE"

cat > "$BIN_DIR/checkmodule" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'checkmodule %s\n' "$*" >> "$TEST_LOG"
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) shift ;;
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
if [[ ${1:-} == "show" ]]; then
  printf '%s\n' "${TEST_MAIN_PID:-4242}"
  exit 0
fi
printf 'systemctl %s\n' "$*" >> "$TEST_LOG"
if [[ ${1:-} == "restart" && ${TEST_RESTART_FAIL:-0} == 1 ]]; then
  exit 1
fi
EOF

cat > "$BIN_DIR/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ps %s\n' "$*" >> "$TEST_LOG"
if [[ ${TEST_DOMAIN:-wifiman_t} == "none" ]]; then
  exit 0
fi
printf 'system_u:system_r:%s:s0\n' "${TEST_DOMAIN:-wifiman_t}"
EOF

cat > "$BIN_DIR/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep %s\n' "$*" >> "$TEST_LOG"
EOF

for tool in restorecon; do
  cat > "$BIN_DIR/$tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TEST_LOG"
EOF
done

cat > "$BIN_DIR/ausearch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ausearch %s\n' "$*" >> "$TEST_LOG"
exit 1
EOF

cat > "$BIN_DIR/audit2allow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'audit2allow %s\n' "$*" >> "$TEST_LOG"
exit 1
EOF

chmod +x "$BIN_DIR"/*

run_installer() {
  env PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" TEST_LOG="$LOG_FILE" \
    APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
    WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 WIFIMAN_SELINUX_POLICY=dedicated \
    "$@" bash "$INSTALLER" > "$WORK_DIR/out.txt" 2>&1
}

# Scenario 1: dedicated policy compiles with file contexts, relabels, starts,
# and verifies the daemon domain.
: > "$LOG_FILE"
run_installer
grep -q 'checkmodule .*wifiman-desktop.te' "$LOG_FILE"
grep -q "semodule_package .*-f $FC_FILE" "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/wifiman-desktop.pp' "$LOG_FILE"
grep -q "restorecon -R $APP_ROOT" "$LOG_FILE"
grep -q "restorecon -R $STATE_ROOT" "$LOG_FILE"
grep -q 'ps -o label= -p 4242' "$LOG_FILE"
grep -q 'systemctl restart wifiman-desktop.service' "$LOG_FILE"
grep -q 'Verified wifiman-desktop.service main PID 4242 runs as wifiman_t' "$WORK_DIR/out.txt"
grep -q 'Installed SELinux base module: wifiman-desktop (variant: dedicated)' "$WORK_DIR/out.txt"
grep -q 'Daemon domain: wifiman_t' "$WORK_DIR/out.txt"
grep -q 'Runtime helper label: wifiman_runtime_exec_t' "$WORK_DIR/out.txt"
if grep -q 'shared init_t' "$WORK_DIR/out.txt"; then
  echo 'dedicated mode must not print the legacy shared-init_t warning' >&2
  exit 1
fi
if grep -q 'checkmodule .*wifiman-desktop-legacy.te' "$LOG_FILE"; then
  echo 'dedicated success must not compile the legacy policy' >&2
  exit 1
fi

# Scenario 2: a failed transition falls back to the legacy policy and exits
# nonzero instead of leaving the daemon unconfined or broken.
: > "$LOG_FILE"
if run_installer TEST_DOMAIN=init_t; then
  echo 'dedicated mode must fail when the daemon does not enter wifiman_t' >&2
  exit 1
fi
grep -q 'wifiman-desktop did not enter wifiman_t' "$WORK_DIR/out.txt"
grep -q 'Restoring the legacy policy' "$WORK_DIR/out.txt"
grep -q "checkmodule .*wifiman-desktop-legacy.te" "$LOG_FILE"
grep -q "restorecon -R $STATE_ROOT" "$LOG_FILE"
grep -q 'systemctl restart wifiman-desktop.service' "$LOG_FILE"

# Scenario 3: a failed restart also falls back and exits nonzero.
: > "$LOG_FILE"
if run_installer TEST_RESTART_FAIL=1; then
  echo 'dedicated mode must fail when the service restart fails' >&2
  exit 1
fi
grep -q 'Restoring the legacy policy' "$WORK_DIR/out.txt"
grep -q "checkmodule .*wifiman-desktop-legacy.te" "$LOG_FILE"

# Scenario 4: explicitly reviewed policy is installed before the first start
# and is not regenerated from AVCs.
reviewed_source="$WORK_DIR/reviewed.te"
cat > "$reviewed_source" <<'EOF'
module wifiman_desktop_local 1.0;
require { type wifiman_t; class tcp_socket name_connect; }
allow wifiman_t self:tcp_socket name_connect;
EOF
: > "$LOG_FILE"
run_installer REVIEWED_AVC_TE="$reviewed_source"
grep -q 'checkmodule .*wifiman_desktop_local.te' "$LOG_FILE"
avc_line=$(grep -n 'semodule -X 300 -i .*/wifiman_desktop_local.pp' "$LOG_FILE" | cut -d: -f1)
restart_line=$(grep -n 'systemctl restart wifiman-desktop.service' "$LOG_FILE" | head -1 | cut -d: -f1)
[[ -n "$avc_line" && -n "$restart_line" && "$avc_line" -lt "$restart_line" ]]
grep -q 'Installed SELinux AVC module: wifiman_desktop_local' "$WORK_DIR/out.txt"
if grep -q '^ausearch ' "$LOG_FILE"; then
  echo 'reviewed AVC install must not run audit generation' >&2
  exit 1
fi

# Scenario 5: an unknown variant fails before changing policy.
: > "$LOG_FILE"
if env PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
  WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 WIFIMAN_SELINUX_POLICY=nonsense \
  bash "$INSTALLER" > "$WORK_DIR/bad.out" 2>&1; then
  echo 'unknown policy variant must fail' >&2
  exit 1
fi
grep -q "Unknown WIFIMAN_SELINUX_POLICY 'nonsense'" "$WORK_DIR/bad.out"
if [[ -s "$LOG_FILE" ]]; then
  echo 'unknown variant must fail before invoking policy tools' >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

# Scenario 6: offline compile of both policy sources when the tools exist.
if command -v checkmodule >/dev/null && command -v semodule_package >/dev/null; then
  mkdir -p "$WORK_DIR/dedicated" "$WORK_DIR/legacy"
  checkmodule -M -m -o "$WORK_DIR/dedicated/wifiman-desktop.mod" "$DEDICATED_TE"
  semodule_package -o "$WORK_DIR/dedicated/wifiman-desktop.pp" -m "$WORK_DIR/dedicated/wifiman-desktop.mod" -f "$FC_FILE"
  checkmodule -M -m -o "$WORK_DIR/legacy/wifiman-desktop.mod" "$LEGACY_TE"
  semodule_package -o "$WORK_DIR/legacy/wifiman-desktop.pp" -m "$WORK_DIR/legacy/wifiman-desktop.mod"
fi

echo "SELinux dedicated-domain installer test passed"
