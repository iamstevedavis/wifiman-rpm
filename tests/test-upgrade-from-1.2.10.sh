#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Installed 1.3.0 layout: no private compat runtime.
APP_ROOT="$WORK_DIR/usr/lib/wi-fiman-desktop"
STATE_ROOT="$WORK_DIR/state"
HOME_DIR="$WORK_DIR/home"
mkdir -p "$APP_ROOT" "$STATE_ROOT/app-root" "$HOME_DIR"

install -m 0644 "$ROOT_DIR/scripts/wifiman-runtime.sh" "$APP_ROOT/wifiman-runtime.sh"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat service.json > "$STATE_ROOT/read-back.txt"
printf '%s\n' "$PWD" > "$STATE_ROOT/pwd.txt"
printf '%s\n' "${LD_LIBRARY_PATH:-}" > "$STATE_ROOT/ld_library_path.txt"
printf '%s\n' "${WEBKIT_EXEC_PATH:-}" > "$STATE_ROOT/webkit_exec_path.txt"
printf '%s\n' "${WEBKIT_INJECTED_BUNDLE_PATH:-}" > "$STATE_ROOT/webkit_injected_bundle_path.txt"
EOF
chmod 0755 "$APP_ROOT/wi-fiman-desktop-bin"

for item in .env .env.development .env.staging wg wg-quick wg_report.sh \
            wifiman-desktopd wireguard-go; do
  printf '#!/bin/sh\n' > "$APP_ROOT/$item"
  chmod 0755 "$APP_ROOT/$item"
done

# Keep the runtime MTU patch on its supported path so the upgrade test does not
# emit a warning unrelated to compat cleanup.
cat > "$APP_ROOT/wg-quick" <<'EOF'
#!/bin/sh
cmd ip link set mtu $(( mtu - 80 )) up dev "$INTERFACE"
EOF
chmod 0755 "$APP_ROOT/wg-quick"

# Existing 1.2.10 user state: a populated compat tree, stale package files and
# a saved service.json pointing into the runtime mirror.
COMPAT="$STATE_ROOT/app-root/compat"
mkdir -p "$COMPAT/lib64/webkit2gtk-4.0/injected-bundle" \
         "$COMPAT/libexec/webkit2gtk-4.0"
printf 'old webkit 4.0\n' > "$COMPAT/lib64/libwebkit2gtk-4.0.so.37"
printf 'old helper\n' > "$COMPAT/libexec/webkit2gtk-4.0/WebKitWebProcess"
printf 'old bundle\n' > "$COMPAT/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"
printf 'stale\n' > "$STATE_ROOT/app-root/old-package-file.txt"
printf '{"saved":"from-1.2.10"}\n' > "$STATE_ROOT/app-root/service.json"
ln -s "$STATE_ROOT/app-root/service.json" "$STATE_ROOT/service.json"

HOME="$HOME_DIR" APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" \
  bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

RUNTIME_ROOT="$STATE_ROOT/app-root"

# The upgrade must remove the old compat tree and any other stale mirror entry.
test ! -e "$RUNTIME_ROOT/compat"
test ! -e "$RUNTIME_ROOT/old-package-file.txt"

# The saved service.json and its symlink must survive the upgrade.
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$RUNTIME_ROOT/service.json"
grep -qx '{"saved":"from-1.2.10"}' "$STATE_ROOT/service.json"
grep -qx '{"saved":"from-1.2.10"}' "$RUNTIME_ROOT/service.json"
grep -qx '{"saved":"from-1.2.10"}' "$STATE_ROOT/read-back.txt"

# The 1.3.0 runtime items must be mirrored, without compat loader exports.
test -f "$RUNTIME_ROOT/wi-fiman-desktop-bin"
test -f "$RUNTIME_ROOT/wg"
test -f "$RUNTIME_ROOT/wg-quick"
test -f "$RUNTIME_ROOT/wg_report.sh"
test -f "$RUNTIME_ROOT/wifiman-desktopd"
test -f "$RUNTIME_ROOT/wireguard-go"
grep -qx "$RUNTIME_ROOT" "$STATE_ROOT/pwd.txt"
grep -qx '' "$STATE_ROOT/ld_library_path.txt"
grep -qx '' "$STATE_ROOT/webkit_exec_path.txt"
grep -qx '' "$STATE_ROOT/webkit_injected_bundle_path.txt"

echo "upgrade from 1.2.10 cleanup test passed"
