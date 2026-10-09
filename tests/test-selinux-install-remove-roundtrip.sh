#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-selinux-policy.sh"
REMOVER="$ROOT_DIR/scripts/remove-wifiman-desktop.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
BIN_DIR="$WORK_DIR/bin"
LOG_FILE="$WORK_DIR/tool.log"
SEMODULE_STATE="$WORK_DIR/semodule-state"
mkdir -p "$BIN_DIR"
: > "$LOG_FILE"
: > "$SEMODULE_STATE"

export TEST_LOG="$LOG_FILE" SEMODULE_STATE="$SEMODULE_STATE"

# Stateful semodule mock: installs are recorded as "<priority> <name>",
# -lfull prints them in the real "<priority> <name> ..." shape, and -r only
# succeeds when the module exists at the requested priority.
cat > "$BIN_DIR/semodule" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'semodule %s\n' "$*" >> "$TEST_LOG"
priority=400
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) priority=$2; shift 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
case "${positional[0]:-}" in
  -i)
    module_name=$(basename "${positional[1]}")
    printf '%s %s\n' "$priority" "${module_name%.pp}" >> "$SEMODULE_STATE"
    ;;
  -lfull)
    if [[ -s "$SEMODULE_STATE" ]]; then
      while read -r prio name; do
        printf '%s %s te\n' "$prio" "$name"
      done < "$SEMODULE_STATE"
    else
      printf 'No modules.\n'
    fi
    ;;
  -r)
    module_name=${positional[1]:-}
    if [[ "${SEMODULE_FAIL_REMOVE:-0}" == "1" ]]; then
      printf 'semodule: forced failure removing %s\n' "$module_name" >&2
      exit 1
    fi
    if grep -qx "$priority $module_name" "$SEMODULE_STATE"; then
      grep -vx "$priority $module_name" "$SEMODULE_STATE" > "$SEMODULE_STATE.tmp" || true
      mv "$SEMODULE_STATE.tmp" "$SEMODULE_STATE"
    else
      printf 'semodule: module %s not found at priority %s\n' "$module_name" "$priority" >&2
      exit 1
    fi
    ;;
esac
EOF

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

cat > "$BIN_DIR/ausearch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ausearch %s\n' "$*" >> "$TEST_LOG"
if printf '%s\n' "$*" | grep -q -- '--raw'; then
  printf 'fake avc raw\n'
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

for tool in systemctl dnf update-desktop-database gtk-update-icon-cache; do
  cat > "$BIN_DIR/$tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TEST_LOG"
EOF
done

cat > "$BIN_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

cat > "$BIN_DIR/rpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rpm %s\n' "$*" >> "$TEST_LOG"
case "${1:-}" in
  -q) exit 1 ;;
  *) exit 0 ;;
esac
EOF

chmod +x "$BIN_DIR"/*

reset_state() {
  : > "$LOG_FILE"
  : > "$SEMODULE_STATE"
  rm -rf "$WORK_DIR/user-state"
}

run_installer() {
  env PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 \
    bash "$INSTALLER" > "$WORK_DIR/install.out" 2>&1 || {
      cat "$WORK_DIR/install.out" >&2
      cat "$LOG_FILE" >&2
      exit 1
    }
}

run_remover() {
  env PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" \
    REMOVE_SYSTEM_STATE=0 USER_STATE_ROOT="$WORK_DIR/user-state" \
    "$@" bash "$REMOVER" > "$WORK_DIR/remove.out" 2>&1
}

# Scenario 1: install then opt-in removal uses matching names at priority 300.
reset_state
run_installer
grep -q 'semodule -X 300 -i .*/wifiman-desktop.pp' "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/wifiman_desktop_local.pp' "$LOG_FILE"
grep -q 'SELinux module priority: 300' "$WORK_DIR/install.out"
grep -qx '300 wifiman-desktop' "$SEMODULE_STATE"
grep -qx '300 wifiman_desktop_local' "$SEMODULE_STATE"

: > "$LOG_FILE"
run_remover REMOVE_SELINUX_MODULES=1
grep -q '^semodule -lfull' "$LOG_FILE"
grep -q 'semodule -X 300 -r wifiman-desktop' "$LOG_FILE"
grep -q 'semodule -X 300 -r wifiman_desktop_local' "$LOG_FILE"
grep -q 'Removing SELinux module wifiman-desktop at priority 300' "$WORK_DIR/remove.out"
grep -q 'Removing SELinux module wifiman_desktop_local at priority 300' "$WORK_DIR/remove.out"
if [[ -s "$SEMODULE_STATE" ]]; then
  echo "expected both SELinux modules to be removed, state still has:" >&2
  cat "$SEMODULE_STATE" >&2
  exit 1
fi

# Scenario 2: default removal preserves SELinux modules.
reset_state
run_installer
: > "$LOG_FILE"
run_remover
if grep -q ' -r ' "$LOG_FILE"; then
  echo "default removal must not remove SELinux modules" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi
grep -q 'Keeping SELinux modules' "$WORK_DIR/remove.out"
grep -qx '300 wifiman-desktop' "$SEMODULE_STATE"
grep -qx '300 wifiman_desktop_local' "$SEMODULE_STATE"

# Scenario 3: module-name overrides stay aligned between install and removal.
reset_state
env PATH="$BIN_DIR:$PATH" HOME="$WORK_DIR" WIFIMAN_ASSUME_ROOT_FOR_TESTS=1 \
  BASE_MODULE_NAME=custom_base AVC_MODULE_NAME=custom_avc \
  bash "$INSTALLER" > "$WORK_DIR/install.out" 2>&1
grep -q 'semodule -X 300 -i .*/custom_base.pp' "$LOG_FILE"
grep -q 'semodule -X 300 -i .*/custom_avc.pp' "$LOG_FILE"
: > "$LOG_FILE"
run_remover REMOVE_SELINUX_MODULES=1 BASE_MODULE_NAME=custom_base AVC_MODULE_NAME=custom_avc
grep -q 'semodule -X 300 -r custom_base' "$LOG_FILE"
grep -q 'semodule -X 300 -r custom_avc' "$LOG_FILE"
if [[ -s "$SEMODULE_STATE" ]]; then
  echo "expected overridden SELinux modules to be removed" >&2
  cat "$SEMODULE_STATE" >&2
  exit 1
fi

# Scenario 4: a failing removal must abort instead of reporting completion.
reset_state
run_installer
: > "$LOG_FILE"
if run_remover REMOVE_SELINUX_MODULES=1 SEMODULE_FAIL_REMOVE=1; then
  echo "expected the removal script to fail when semodule -r fails" >&2
  cat "$WORK_DIR/remove.out" >&2
  exit 1
fi

echo "SELinux install/remove round-trip test passed"
