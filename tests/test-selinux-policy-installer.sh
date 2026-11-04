#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-selinux-policy.sh"
DEDICATED_TE="$ROOT_DIR/scripts/wifiman-desktop.te"
LEGACY_TE="$ROOT_DIR/scripts/wifiman-desktop-legacy.te"
FC_FILE="$ROOT_DIR/scripts/wifiman-desktop.fc"

bash -n "$INSTALLER"

# Dedicated policy: a real domain transition and WiFiman-specific object types.
grep -q '^module wifiman-desktop ' "$DEDICATED_TE"
grep -q '^type wifiman_t, domain;' "$DEDICATED_TE"
grep -q '^type wifiman_exec_t, file_type, exec_type;' "$DEDICATED_TE"
grep -q '^type wifiman_helper_exec_t, file_type, exec_type;' "$DEDICATED_TE"
grep -q '^type wifiman_lib_t, file_type;' "$DEDICATED_TE"
grep -q '^type wifiman_var_t, file_type;' "$DEDICATED_TE"
grep -q 'type_transition init_t wifiman_exec_t:process wifiman_t;' "$DEDICATED_TE"
grep -q 'allow init_t wifiman_t:process { transition noatsecure rlimitinh siginh };' "$DEDICATED_TE"
grep -q 'allow wifiman_t wifiman_exec_t:file { entrypoint' "$DEDICATED_TE"
grep -q 'allow wifiman_t self:tcp_socket' "$DEDICATED_TE"
grep -q 'allow wifiman_t self:rawip_socket' "$DEDICATED_TE"
grep -q 'allow wifiman_t self:netlink_generic_socket' "$DEDICATED_TE"
grep -q 'allow wifiman_t node_t:rawip_socket node_bind;' "$DEDICATED_TE"
grep -q 'allow wifiman_t node_t:tcp_socket node_bind;' "$DEDICATED_TE"
grep -q '^role system_r types wifiman_t;' "$DEDICATED_TE"
grep -q 'allow wifiman_t mysqld_port_t:tcp_socket' "$DEDICATED_TE"
grep -q 'allow wifiman_t http_port_t:tcp_socket name_connect;' "$DEDICATED_TE"
grep -q 'allow wifiman_t tun_tap_device_t:chr_file' "$DEDICATED_TE"
grep -q 'type_transition wifiman_t wifiman_var_t:file wifiman_helper_exec_t "wifiman-desktopd";' "$DEDICATED_TE"
grep -q 'allow wifiman_t wifiman_var_t:file' "$DEDICATED_TE"
grep -q 'allow wifiman_t wifiman_lib_t:file' "$DEDICATED_TE"

# The dedicated module must not add writes to shared generic file labels or
# networking grants on the shared init_t domain.
if grep -Eq '^allow init_t (lib_t|var_lib_t|init_var_lib_t):' "$DEDICATED_TE"; then
  echo 'dedicated policy must not grant shared object types to init_t' >&2
  exit 1
fi
if grep -Eq '^allow init_t .*:tcp_socket|^allow init_t .*:rawip_socket|^allow init_t .*:netlink' "$DEDICATED_TE"; then
  echo 'dedicated policy must not grant networking to init_t' >&2
  exit 1
fi

# File contexts map the entry point, helpers, packaged data and state.
grep -q '^/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper.*wifiman_exec_t' "$FC_FILE"
grep -q '^/usr/lib/wi-fiman-desktop/wifiman-desktopd.*wifiman_helper_exec_t' "$FC_FILE"
grep -q '^/usr/lib/wi-fiman-desktop/wg.*wifiman_helper_exec_t' "$FC_FILE"
grep -q '^/usr/lib/wi-fiman-desktop(/\.\*)?.*wifiman_lib_t' "$FC_FILE"
grep -q '^/var/lib/wifiman-desktop(/\.\*)?.*wifiman_var_t' "$FC_FILE"
grep -q '^/var/lib/wifiman-desktop/app-root/wg-quick.*wifiman_helper_exec_t' "$FC_FILE"
grep -q '^/var/lib/wifiman-desktop/app-root/wifiman-desktopd.*wifiman_helper_exec_t' "$FC_FILE"

# Legacy policy is retained for explicit fallback and still documents its scope.
grep -q '^module wifiman-desktop ' "$LEGACY_TE"
grep -q 'allow init_t lib_t:file ' "$LEGACY_TE"
grep -q 'allow init_t var_lib_t:file ' "$LEGACY_TE"
grep -q 'allow init_t self:rawip_socket' "$LEGACY_TE"

grep -q 'WIFIMAN_ASSUME_ROOT_FOR_TESTS' "$INSTALLER"
grep -q 'BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}' "$INSTALLER"
grep -q 'AVC_MODULE_NAME=' "$INSTALLER"
grep -q 'POLICY_VARIANT=${WIFIMAN_SELINUX_POLICY:-dedicated}' "$INSTALLER"
grep -q 'compile_and_install' "$INSTALLER"
grep -q 'audit2allow -m "\$AVC_MODULE_NAME"' "$INSTALLER"
grep -q 'REVIEWED_AVC_TE=' "$INSTALLER"
grep -q 'relabel_dedicated' "$INSTALLER"
grep -q 'verify_dedicated_domain' "$INSTALLER"
grep -q 'revert_to_legacy' "$INSTALLER"
grep -q 'restorecon -R "\$APP_ROOT"' "$INSTALLER"
grep -q 'restorecon -R "\$STATE_ROOT"' "$INSTALLER"
grep -q 'semodule_package -o "\$TMP_DIR/\$module_name.pp" -m "\$TMP_DIR/\$module_name.mod" -f "\$fc_path"' "$INSTALLER"

python3 - <<'PY' "$INSTALLER"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert '>> "$TMP_DIR/' not in text, 'installer should not append AVC policy into base TE file'
assert 'cp "$BASE_TE" "$TMP_DIR/$BASE_MODULE_NAME.te"' in text
assert 'compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te" "$DEDICATED_FC"' in text
assert 'compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te"' in text
assert 'compile_and_install "$BASE_MODULE_NAME" "$LEGACY_TE"' in text
assert 'WIFIMAN_ASSUME_ROOT_FOR_TESTS' in text
assert 'BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}' in text
assert 'audit2allow -m "$AVC_MODULE_NAME"' in text
assert 'audit2allow -M' not in text, 'unreviewed AVCs must not produce installable modules'
assert 'cp "$REVIEWED_AVC_TE" "$TMP_DIR/$AVC_MODULE_NAME.te"' in text
assert '>/dev/null 2>&1 || true' not in text, 'generation errors must not be suppressed'
assert 'SELINUX_MODULE_PRIORITY=${SELINUX_MODULE_PRIORITY:-300}' in text
assert 'semodule -X "$SELINUX_MODULE_PRIORITY" -i "$TMP_DIR/$module_name.pp"' in text
assert 'compile_and_install "$AVC_MODULE_NAME" "$TMP_DIR/$AVC_MODULE_NAME.te"' in text
print('selinux installer structure OK')
PY

echo "SELinux policy installer tests passed"
