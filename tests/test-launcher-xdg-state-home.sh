#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
HOME_DIR="$WORK_DIR/home"
XDG_DIR="$WORK_DIR/xdg-state"
mkdir -p "$APP_ROOT" "$HOME_DIR" "$XDG_DIR"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD" > "$HOME/pwd.txt"
printf '%s\n' "${LOG_DIR:-}" > "$HOME/log_dir.txt"
printf 'xdg-seed\n' > service.json.tmp
mv service.json.tmp service.json
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

HOME="$HOME_DIR" XDG_STATE_HOME="$XDG_DIR" APP_ROOT="$APP_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

STATE_ROOT="$XDG_DIR/wifiman-desktop"
test -d "$STATE_ROOT/app-root"
test -L "$STATE_ROOT/service.json"
grep -qx "$STATE_ROOT/app-root" "$HOME_DIR/pwd.txt"
grep -qx "$STATE_ROOT" "$HOME_DIR/log_dir.txt"
grep -qx 'xdg-seed' "$STATE_ROOT/service.json"

echo "launcher XDG state home test passed"
