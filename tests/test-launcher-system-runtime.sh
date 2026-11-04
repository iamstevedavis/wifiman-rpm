#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT/compat/lib64" "$STATE_ROOT/app-root/compat/lib64"

# A leftover private runtime from a pre-1.3.0 install must not survive.
printf 'stale\n' > "$STATE_ROOT/app-root/compat/lib64/libwebkit2gtk-4.0.so"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" > "$STATE_ROOT/pwd.txt"
printf '%s\n' "${LD_LIBRARY_PATH:-}" > "$STATE_ROOT/ld_library_path.txt"
printf '%s\n' "${WEBKIT_EXEC_PATH:-}" > "$STATE_ROOT/webkit_exec_path.txt"
printf '%s\n' "${WEBKIT_INJECTED_BUNDLE_PATH:-}" > "$STATE_ROOT/webkit_injected_bundle_path.txt"
printf '%s\n' "${WEBKIT_FORCE_SANDBOX:-}" > "$STATE_ROOT/webkit_force_sandbox.txt"
printf '%s\n' "${LOG_DIR:-}" > "$STATE_ROOT/log_dir.txt"
printf '%s\n' "${LOG_PATH:-}" > "$STATE_ROOT/log_path.txt"
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

# Upstream 1.3.0 ships its WebKit payload in the host package, not in the app.
printf 'should-not-be-mirrored\n' > "$APP_ROOT/compat/lib64/libwebkit2gtk-4.0.so"

env -u LD_LIBRARY_PATH -u WEBKIT_EXEC_PATH -u WEBKIT_INJECTED_BUNDLE_PATH \
    -u WEBKIT_FORCE_SANDBOX \
    APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
    bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

RUNTIME_ROOT="$STATE_ROOT/app-root"

grep -qx "$RUNTIME_ROOT" "$STATE_ROOT/pwd.txt"
grep -qx '' "$STATE_ROOT/ld_library_path.txt"
grep -qx '' "$STATE_ROOT/webkit_exec_path.txt"
grep -qx '' "$STATE_ROOT/webkit_injected_bundle_path.txt"
grep -qx '' "$STATE_ROOT/webkit_force_sandbox.txt"
grep -qx "$STATE_ROOT" "$STATE_ROOT/log_dir.txt"
grep -qx "$STATE_ROOT/wifiman-desktop.log" "$STATE_ROOT/log_path.txt"

# The launcher must rely on the system WebKitGTK 4.1 stack, not a mirror.
test ! -e "$RUNTIME_ROOT/compat"
test ! -e "$RUNTIME_ROOT/wifiman-runtime.sh"

echo "launcher system runtime test passed"
