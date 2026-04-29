#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT" "$STATE_ROOT"

cat > "$APP_ROOT/wifiman-desktopd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" > "$STATE_ROOT/pwd.txt"
printf '%s\n' "$0" > "$STATE_ROOT/argv0.txt"
printf '%s\n' "${LOG_DIR:-}" > "$STATE_ROOT/log_dir.txt"
printf '%s\n' "${LOG_PATH:-}" > "$STATE_ROOT/log_path.txt"
printf 'seed\n' > service.json.tmp
mv service.json.tmp service.json
EOF
chmod +x "$APP_ROOT/wifiman-desktopd"
printf 'package-owned\n' > "$APP_ROOT/package.txt"
printf '{"original":true}\n' > "$APP_ROOT/service.json"

APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh"

test -d "$STATE_ROOT/app-root"
test -L "$STATE_ROOT/app-root/wifiman-desktopd"
test -L "$STATE_ROOT/app-root/package.txt"
test ! -L "$STATE_ROOT/app-root/service.json"
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$STATE_ROOT/app-root/service.json"
test ! -e "$STATE_ROOT/service.json.tmp"
grep -qx "$STATE_ROOT/app-root" "$STATE_ROOT/pwd.txt"
grep -qx "$STATE_ROOT/app-root/wifiman-desktopd" "$STATE_ROOT/argv0.txt"
grep -qx "$STATE_ROOT" "$STATE_ROOT/log_dir.txt"
grep -qx "$STATE_ROOT/wifiman-desktop.log" "$STATE_ROOT/log_path.txt"
grep -qx 'seed' "$STATE_ROOT/app-root/service.json"
grep -qx 'seed' "$STATE_ROOT/service.json"
grep -qx '{"original":true}' "$APP_ROOT/service.json"

echo "runtime wrapper test passed"
