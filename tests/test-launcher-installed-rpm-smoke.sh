#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Build an installed tree the way wifiman-desktop.spec lays it out.
APP_ROOT="$WORK_DIR/usr/lib/wi-fiman-desktop"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT" "$STATE_ROOT" "$WORK_DIR/usr/bin"
install -m 0755 "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh" "$WORK_DIR/usr/bin/wifiman-desktop"
install -m 0644 "$ROOT_DIR/scripts/wifiman-runtime.sh" "$APP_ROOT/wifiman-runtime.sh"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${LD_LIBRARY_PATH:-}" > "$STATE_ROOT/ld_library_path.txt"
printf '%s\n' "${WEBKIT_EXEC_PATH:-}" > "$STATE_ROOT/webkit_exec_path.txt"
printf '%s\n' "${WEBKIT_INJECTED_BUNDLE_PATH:-}" > "$STATE_ROOT/webkit_injected_bundle_path.txt"
printf '%s\n' "${WEBKIT_FORCE_SANDBOX:-}" > "$STATE_ROOT/webkit_force_sandbox.txt"
printf '%s\n' "$PWD" > "$STATE_ROOT/pwd.txt"
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

printf '.env\n' > "$APP_ROOT/.env"
printf '#!/bin/sh\n' > "$APP_ROOT/wg"
chmod +x "$APP_ROOT/wg"
printf '#!/bin/sh\n' > "$APP_ROOT/wg-quick"
chmod +x "$APP_ROOT/wg-quick"
printf '#!/bin/sh\n' > "$APP_ROOT/wg_report.sh"
chmod +x "$APP_ROOT/wg_report.sh"
printf 'wireguard-go\n' > "$APP_ROOT/wireguard-go"
printf 'daemon\n' > "$APP_ROOT/wifiman-desktopd"

# Mock installed-layout launch: no compat/library variables in the parent env.
env -u LD_LIBRARY_PATH -u WEBKIT_EXEC_PATH -u WEBKIT_INJECTED_BUNDLE_PATH \
    -u WEBKIT_FORCE_SANDBOX \
    APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
    "$WORK_DIR/usr/bin/wifiman-desktop"

RUNTIME_ROOT="$STATE_ROOT/app-root"

# Upstream 1.3.0 uses the host WebKitGTK 4.1 stack; nothing app-private is mirrored.
test ! -e "$RUNTIME_ROOT/compat"
test ! -e "$RUNTIME_ROOT/wifiman-runtime.sh"
test -f "$RUNTIME_ROOT/.env"
test -f "$RUNTIME_ROOT/wg"
test -f "$RUNTIME_ROOT/wg-quick"
test -f "$RUNTIME_ROOT/wg_report.sh"
test -f "$RUNTIME_ROOT/wireguard-go"
test -f "$RUNTIME_ROOT/wifiman-desktopd"

# The child must run from the runtime mirror without loader/WebKit overrides.
grep -qx "$RUNTIME_ROOT" "$STATE_ROOT/pwd.txt"
grep -qx '' "$STATE_ROOT/ld_library_path.txt"
grep -qx '' "$STATE_ROOT/webkit_exec_path.txt"
grep -qx '' "$STATE_ROOT/webkit_injected_bundle_path.txt"
grep -qx '' "$STATE_ROOT/webkit_force_sandbox.txt"

echo "launcher installed-RPM smoke test passed"
