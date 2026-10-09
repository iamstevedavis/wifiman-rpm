#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT" "$STATE_ROOT"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${LD_LIBRARY_PATH:-}" > "$STATE_ROOT/ld_library_path.txt"
printf '%s\n' "${WEBKIT_EXEC_PATH:-}" > "$STATE_ROOT/webkit_exec_path.txt"
printf '%s\n' "${WEBKIT_INJECTED_BUNDLE_PATH:-}" > "$STATE_ROOT/webkit_injected_bundle_path.txt"
printf '%s\n' "${WEBKIT_FORCE_SANDBOX:-}" > "$STATE_ROOT/webkit_force_sandbox.txt"
printf '%s\n' "${LOG_DIR:-}" > "$STATE_ROOT/log_dir.txt"
printf '%s\n' "${LOG_PATH:-}" > "$STATE_ROOT/log_path.txt"
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

mkdir -p "$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle" \
         "$APP_ROOT/compat/libexec/webkit2gtk-4.0"
printf 'lib\n' > "$APP_ROOT/compat/lib64/libwebkit2gtk.so"
printf 'helper\n' > "$APP_ROOT/compat/libexec/webkit2gtk-4.0/WebKitWebProcess"
printf 'bundle\n' > "$APP_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

# A pre-existing loader path must be preserved behind the compat dir.
LD_LIBRARY_PATH=/opt/custom/lib APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
  bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

RUNTIME_ROOT="$STATE_ROOT/app-root"
grep -qx "$RUNTIME_ROOT/compat/lib64:/opt/custom/lib" "$STATE_ROOT/ld_library_path.txt"
grep -qx "$RUNTIME_ROOT/compat/libexec/webkit2gtk-4.0" "$STATE_ROOT/webkit_exec_path.txt"
grep -qx "$RUNTIME_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so" \
  "$STATE_ROOT/webkit_injected_bundle_path.txt"
# The staged wrapper's sandbox-disabling workaround must not be copied blindly.
grep -qx '' "$STATE_ROOT/webkit_force_sandbox.txt"
grep -qx "$STATE_ROOT" "$STATE_ROOT/log_dir.txt"
grep -qx "$STATE_ROOT/wifiman-desktop.log" "$STATE_ROOT/log_path.txt"

echo "launcher compat env test passed"
