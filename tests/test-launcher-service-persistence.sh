#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
STATE_ROOT="$WORK_DIR/state-root"
mkdir -p "$APP_ROOT" "$STATE_ROOT"

# Mock launcher that only reads service.json — does NOT overwrite it.
cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat service.json > "$STATE_ROOT/read-back.txt"
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

# First invocation: wrapper seeds {} and creates symlink.
APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

# Verify first run produced a valid symlink.
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$STATE_ROOT/app-root/service.json"

# Simulate the app saving configuration.
printf '{"saved":"must-survive"}\n' > "$STATE_ROOT/app-root/service.json"

# Second invocation: wrapper must NOT discard the saved config.
APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" bash "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"

# The saved config must survive unchanged.
grep -qx '{"saved":"must-survive"}' "$STATE_ROOT/app-root/service.json"
grep -qx '{"saved":"must-survive"}' "$STATE_ROOT/service.json"

# The mock should have read back the saved config on the second run.
grep -qx '{"saved":"must-survive"}' "$STATE_ROOT/read-back.txt"

# Symlink must still be valid.
test -L "$STATE_ROOT/service.json"
test "$(readlink "$STATE_ROOT/service.json")" = "$STATE_ROOT/app-root/service.json"

echo "launcher service persistence test passed"
