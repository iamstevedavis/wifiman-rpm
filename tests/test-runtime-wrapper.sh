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
printf '%s\n' "$(readlink -f "$0")" > "$STATE_ROOT/resolved_argv0.txt"
printf '%s\n' "${LOG_DIR:-}" > "$STATE_ROOT/log_dir.txt"
printf '%s\n' "${LOG_PATH:-}" > "$STATE_ROOT/log_path.txt"
exe_dir=$(dirname "$(readlink -f "$0")")
printf '%s\n' "$exe_dir/wg-runtime.conf" > "$STATE_ROOT/wg_conf_path.txt"
printf 'runtime-conf\n' > "$exe_dir/wg-runtime.conf"
printf 'seed\n' > service.json.tmp
mv service.json.tmp service.json
EOF
chmod +x "$APP_ROOT/wifiman-desktopd"
printf 'package-owned\n' > "$APP_ROOT/package.txt"
printf '{"original":true}\n' > "$APP_ROOT/service.json"
printf 'stale log\n' > "$APP_ROOT/wifiman-desktop.log"
printf '[Unit]\n' > "$APP_ROOT/wifiman-desktop.service"
mkdir -p "$APP_ROOT/compat"
printf '#!/usr/bin/env bash\n' > "$APP_ROOT/wg"
chmod +x "$APP_ROOT/wg"

APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh"

test -d "$STATE_ROOT/app-root"
test -f "$STATE_ROOT/app-root/wifiman-desktopd"
test -d "$STATE_ROOT/app-root/compat"
test -f "$STATE_ROOT/app-root/wg"
test ! -e "$STATE_ROOT/app-root/package.txt"
test ! -e "$STATE_ROOT/app-root/wifiman-desktop.log"
test ! -e "$STATE_ROOT/app-root/wifiman-desktop.service"
test ! -L "$STATE_ROOT/app-root/service.json"
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$STATE_ROOT/app-root/service.json"
test ! -e "$STATE_ROOT/service.json.tmp"
test -f "$STATE_ROOT/app-root/wg-runtime.conf"
grep -qx "$STATE_ROOT/app-root" "$STATE_ROOT/pwd.txt"
grep -qx "$STATE_ROOT/app-root/wifiman-desktopd" "$STATE_ROOT/argv0.txt"
grep -qx "$STATE_ROOT/app-root/wifiman-desktopd" "$STATE_ROOT/resolved_argv0.txt"
grep -qx "$STATE_ROOT/app-root/wg-runtime.conf" "$STATE_ROOT/wg_conf_path.txt"
grep -qx "$STATE_ROOT" "$STATE_ROOT/log_dir.txt"
grep -qx "$STATE_ROOT/wifiman-desktop.log" "$STATE_ROOT/log_path.txt"
grep -qx 'seed' "$STATE_ROOT/app-root/service.json"
grep -qx 'seed' "$STATE_ROOT/service.json"
grep -qx '{"original":true}' "$APP_ROOT/service.json"
test ! -e "$APP_ROOT/wg-runtime.conf"

echo "runtime wrapper test passed"
