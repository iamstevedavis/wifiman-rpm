#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Build an installed tree the way wifiman-desktop.spec lays it out.
APP_ROOT="$WORK_DIR/usr/lib/wi-fiman-desktop"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle" \
         "$APP_ROOT/compat/libexec/webkit2gtk-4.0" "$STATE_ROOT"

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

printf 'compat-lib\n' > "$APP_ROOT/compat/lib64/libwebkit2gtk.so"
printf 'helper\n' > "$APP_ROOT/compat/libexec/webkit2gtk-4.0/WebKitWebProcess"
printf 'bundle\n' > "$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"
printf '.env\n' > "$APP_ROOT/.env"
printf '#!/bin/sh\n' > "$APP_ROOT/wg"
chmod +x "$APP_ROOT/wg"
printf '#!/bin/sh\n' > "$APP_ROOT/wg-quick"
chmod +x "$APP_ROOT/wg-quick"
printf '#!/bin/sh\n' > "$APP_ROOT/wg_report.sh"
chmod +x "$APP_ROOT/wg_report.sh"
printf 'wireguard-go\n' > "$APP_ROOT/wireguard-go"
printf 'daemon\n' > "$APP_ROOT/wifiman-desktopd"

# Clean newer-Fedora launch: no compat/library variables in the parent env.
env -u LD_LIBRARY_PATH -u WEBKIT_EXEC_PATH -u WEBKIT_INJECTED_BUNDLE_PATH \
    -u WEBKIT_FORCE_SANDBOX \
    APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
    bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

RUNTIME_ROOT="$STATE_ROOT/app-root"

# The compat runtime must be mirrored into the per-user runtime root.
test -f "$RUNTIME_ROOT/compat/lib64/libwebkit2gtk.so"
test -f "$RUNTIME_ROOT/compat/libexec/webkit2gtk-4.0/WebKitWebProcess"
test -f "$RUNTIME_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

# The child must run from the runtime mirror and see compat paths relative to it.
grep -qx "$RUNTIME_ROOT" "$STATE_ROOT/pwd.txt"
grep -qx "$RUNTIME_ROOT/compat/lib64" "$STATE_ROOT/ld_library_path.txt"
grep -qx "$RUNTIME_ROOT/compat/libexec/webkit2gtk-4.0" "$STATE_ROOT/webkit_exec_path.txt"
grep -qx "$RUNTIME_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so" \
  "$STATE_ROOT/webkit_injected_bundle_path.txt"
grep -qx '' "$STATE_ROOT/webkit_force_sandbox.txt"

echo "launcher installed-RPM smoke test passed"
