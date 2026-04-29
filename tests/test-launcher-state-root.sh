#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
HOME_DIR="$WORK_DIR/home"
mkdir -p "$APP_ROOT" "$HOME_DIR"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" > "$HOME/pwd.txt"
printf '%s\n' "$0" > "$HOME/argv0.txt"
printf '%s\n' "${LOG_DIR:-}" > "$HOME/log_dir.txt"
printf '%s\n' "${LOG_PATH:-}" > "$HOME/log_path.txt"
printf 'ui-seed\n' > service.json.tmp
mv service.json.tmp service.json
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"
printf 'package-owned\n' > "$APP_ROOT/package.txt"
printf '{"original":true}\n' > "$APP_ROOT/service.json"

HOME="$HOME_DIR" APP_ROOT="$APP_ROOT" bash "$ROOT_DIR/scripts/wi-fiman-desktop-launcher.sh"

STATE_ROOT="$HOME_DIR/.local/state/wifiman-desktop"
test -d "$STATE_ROOT/app-root"
test -L "$STATE_ROOT/app-root/wi-fiman-desktop-bin"
test -L "$STATE_ROOT/app-root/package.txt"
test ! -L "$STATE_ROOT/app-root/service.json"
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$STATE_ROOT/app-root/service.json"
grep -qx "$STATE_ROOT/app-root" "$HOME_DIR/pwd.txt"
grep -qx "$STATE_ROOT/app-root/wi-fiman-desktop-bin" "$HOME_DIR/argv0.txt"
grep -qx "$STATE_ROOT" "$HOME_DIR/log_dir.txt"
grep -qx "$STATE_ROOT/wifiman-desktop.log" "$HOME_DIR/log_path.txt"
grep -qx 'ui-seed' "$STATE_ROOT/service.json"
grep -qx '{"original":true}' "$APP_ROOT/service.json"

echo "launcher state root test passed"
