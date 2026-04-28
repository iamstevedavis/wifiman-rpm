#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT_DIR/scripts/install-selinux-policy.sh"
BASE_TE="$ROOT_DIR/scripts/wifiman-desktop.te"

bash -n "$INSTALLER"

grep -q '^module wifiman-desktop ' "$BASE_TE"
grep -q 'class rawip_socket { bind setopt };' "$BASE_TE"
grep -q 'allow init_t self:rawip_socket { bind setopt };' "$BASE_TE"
grep -q 'WIFIMAN_ASSUME_ROOT_FOR_TESTS' "$INSTALLER"
grep -q 'BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}' "$INSTALLER"
grep -q 'AVC_MODULE_NAME=' "$INSTALLER"
grep -q 'compile_and_install' "$INSTALLER"
grep -q 'audit2allow -M "\$AVC_MODULE_NAME"' "$INSTALLER"
grep -q 'cd "\$TMP_DIR"' "$INSTALLER"
grep -q 'if \[\[ -f "\$TMP_DIR/\$AVC_MODULE_NAME.te" && -f "\$TMP_DIR/\$AVC_MODULE_NAME.pp" \]\]' "$INSTALLER"

python3 - <<'PY' "$INSTALLER"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert '>> "$TMP_DIR/' not in text, 'installer should not append AVC policy into base TE file'
assert 'cp "$BASE_TE" "$TMP_DIR/$BASE_MODULE_NAME.te"' in text
assert 'compile_and_install "$BASE_MODULE_NAME" "$TMP_DIR/$BASE_MODULE_NAME.te"' in text
assert 'WIFIMAN_ASSUME_ROOT_FOR_TESTS' in text
assert 'BASE_MODULE_NAME=${BASE_MODULE_NAME:-wifiman-desktop}' in text
assert 'audit2allow -M "$AVC_MODULE_NAME"' in text
assert 'cd "$TMP_DIR"' in text
assert 'if [[ -f "$TMP_DIR/$AVC_MODULE_NAME.te" && -f "$TMP_DIR/$AVC_MODULE_NAME.pp" ]]' in text
assert 'semodule -X 300 -i "$TMP_DIR/$AVC_MODULE_NAME.pp"' in text
print('selinux installer structure OK')
PY

echo "SELinux policy installer tests passed"
