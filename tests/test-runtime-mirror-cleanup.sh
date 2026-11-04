#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT" "$STATE_ROOT/app-root"

cat > "$APP_ROOT/wifiman-desktopd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cleanup-seed\n' > service.json.tmp
mv service.json.tmp service.json
EOF
chmod +x "$APP_ROOT/wifiman-desktopd"
printf '#!/usr/bin/env bash\n' > "$APP_ROOT/wg"
chmod +x "$APP_ROOT/wg"

# Stale entries from older wrappers, including the removed compat runtime.
printf 'stale\n' > "$STATE_ROOT/app-root/old-file.txt"
mkdir -p "$STATE_ROOT/app-root/compat/lib64"
printf 'stale compat\n' > "$STATE_ROOT/app-root/compat/lib64/libwebkit2gtk-4.0.so"
ln -sfn /tmp/nowhere "$STATE_ROOT/app-root/wifiman-desktop.log"
ln -sfn /tmp/nowhere "$STATE_ROOT/app-root/wifiman-desktop.service"

APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh"

test -f "$STATE_ROOT/app-root/wifiman-desktopd"
test ! -e "$STATE_ROOT/app-root/compat"
test -f "$STATE_ROOT/app-root/wg"
test ! -e "$STATE_ROOT/app-root/old-file.txt"
test ! -e "$STATE_ROOT/app-root/wifiman-desktop.log"
test ! -e "$STATE_ROOT/app-root/wifiman-desktop.service"
test ! -e "$STATE_ROOT/app-root/service.json.tmp"
grep -qx 'cleanup-seed' "$STATE_ROOT/service.json"

echo "runtime mirror cleanup test passed"
