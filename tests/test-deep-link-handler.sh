#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
BIN_DIR="$WORK_DIR/bin"
mkdir -p "$APP_ROOT" "$BIN_DIR"

LAUNCHER="$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
SCHEME='x-scheme-handler/wifiman-desktop-dl'
HANDLER_NAME='wi-fiman-desktop-bin-handler.desktop'

# The handler name must follow the mirrored UI binary name, because the plugin
# derives its filename from the running executable's basename.
grep -qx 'UI_BINARY_NAME=wi-fiman-desktop-bin' "$LAUNCHER"
grep -qx 'DEEP_LINK_HANDLER_NAME="$UI_BINARY_NAME-handler.desktop"' "$LAUNCHER"

# The launcher falls back to the helper next to APP_ROOT when it is copied away
# from scripts/ (as in the installed /usr/bin layout).
cp "$ROOT_DIR/scripts/wifiman-runtime.sh" "$APP_ROOT/wifiman-runtime.sh"

cat > "$APP_ROOT/wi-fiman-desktop-bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$HOME/deep-link-args.txt"
EOF
chmod +x "$APP_ROOT/wi-fiman-desktop-bin"

# Keep the test hermetic: record xdg-mime calls and track the association in a
# state file instead of touching the real user's mimeapps.list.
cat > "$BIN_DIR/xdg-mime" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$XDG_MIME_LOG"
if [[ "$1" == query ]]; then
  [[ -s "$XDG_MIME_STATE" ]] && cat "$XDG_MIME_STATE"
  exit 0
fi
if [[ "$1" == default ]]; then
  printf '%s\n' "$2" > "$XDG_MIME_STATE"
  exit 0
fi
exit 2
EOF
chmod +x "$BIN_DIR/xdg-mime"

cat > "$BIN_DIR/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$XDG_DESKTOP_DB_LOG"
EOF
chmod +x "$BIN_DIR/update-desktop-database"

MIME_STATE="$WORK_DIR/mime-default"
MIME_LOG="$WORK_DIR/xdg-mime.log"
DB_LOG="$WORK_DIR/desktop-db.log"

run_launcher() {
  local launcher=$1 home=$2 data=$3 config=$4
  HOME="$home" \
  XDG_DATA_HOME="$data" \
  XDG_CONFIG_HOME="$config" \
  XDG_MIME_STATE="$MIME_STATE" \
  XDG_MIME_LOG="$MIME_LOG" \
  XDG_DESKTOP_DB_LOG="$DB_LOG" \
  PATH="$BIN_DIR:$PATH" \
  APP_ROOT="$APP_ROOT" \
  bash "$launcher" "wifiman-desktop-dl://invite/test"
}

# Scenario 1: a stale plugin handler points at the raw binary and has no Icon.
# The launcher must rewrite it to use the wrapper instead.
HOME_DIR="$WORK_DIR/home"
XDG_DATA_DIR="$WORK_DIR/data"
XDG_CONFIG_DIR="$WORK_DIR/config"
mkdir -p "$HOME_DIR" "$XDG_DATA_DIR" "$XDG_CONFIG_DIR"
HANDLER="$XDG_DATA_DIR/applications/$HANDLER_NAME"
mkdir -p "$(dirname "$HANDLER")"
cat > "$HANDLER" <<'EOF'
[Desktop Entry]
Type=Application
Name=WiFiman Desktop
Exec="/usr/lib/wi-fiman-desktop/wi-fiman-desktop-bin" %u
Terminal=false
MimeType=x-scheme-handler/wifiman-desktop-dl;
NoDisplay=true
EOF
printf '%s\n' "$HANDLER_NAME" > "$MIME_STATE"
: > "$MIME_LOG"
: > "$DB_LOG"

run_launcher "$LAUNCHER" "$HOME_DIR" "$XDG_DATA_DIR" "$XDG_CONFIG_DIR"

grep -qx 'wifiman-desktop-dl://invite/test' "$HOME_DIR/deep-link-args.txt"
grep -Fqx "Exec=\"$LAUNCHER\" %u" "$HANDLER"
grep -qx "MimeType=$SCHEME;" "$HANDLER"
grep -qx 'Icon=wifiman-desktop' "$HANDLER"
grep -qx 'NoDisplay=true' "$HANDLER"
! grep -q '/usr/lib/wi-fiman-desktop/wi-fiman-desktop-bin' "$HANDLER"
grep -Fq "query default $SCHEME" "$MIME_LOG"
# The default already used the managed handler name, so it was left alone.
! grep -Fq "default $HANDLER_NAME" "$MIME_LOG"
grep -Fqx "$XDG_DATA_DIR/applications" "$DB_LOG"
test -z "$(find "$XDG_DATA_DIR/applications" -maxdepth 1 -name '.wifiman-deep-link.*' -print -quit)"

# Scenario 2: with no handler and no default, the launcher must create the
# handler and point the scheme at it before the app can register its own.
rm -rf "$XDG_DATA_DIR/applications" "$HOME_DIR/deep-link-args.txt"
: > "$MIME_STATE"
: > "$MIME_LOG"
: > "$DB_LOG"

run_launcher "$LAUNCHER" "$HOME_DIR" "$XDG_DATA_DIR" "$XDG_CONFIG_DIR"

grep -Fqx "Exec=\"$LAUNCHER\" %u" "$HANDLER"
grep -qx "MimeType=$SCHEME;" "$HANDLER"
grep -Fq "default $HANDLER_NAME $SCHEME" "$MIME_LOG"
grep -qx "$HANDLER_NAME" "$MIME_STATE"

# Scenario 3: a launcher path with desktop-entry metacharacters is escaped in
# Exec=. The helper is found through the APP_ROOT fallback.
WEIRD_DIR="$WORK_DIR/weird \"quote\" \$cash %percent \`tick\`"
WEIRD_HOME="$WORK_DIR/weird-home"
WEIRD_DATA="$WORK_DIR/weird-data"
WEIRD_CONFIG="$WORK_DIR/weird-config"
mkdir -p "$WEIRD_DIR" "$WEIRD_HOME" "$WEIRD_DATA" "$WEIRD_CONFIG"
WEIRD_LAUNCHER="$WEIRD_DIR/wifiman-desktop-launcher.sh"
cp "$LAUNCHER" "$WEIRD_LAUNCHER"
: > "$MIME_STATE"
: > "$MIME_LOG"
: > "$DB_LOG"

run_launcher "$WEIRD_LAUNCHER" "$WEIRD_HOME" "$WEIRD_DATA" "$WEIRD_CONFIG"

WEIRD_HANDLER="$WEIRD_DATA/applications/$HANDLER_NAME"
escaped=$WEIRD_LAUNCHER
escaped=${escaped//\\/\\\\}
escaped=${escaped//\`/\\\`}
escaped=${escaped//\$/\\\$}
escaped=${escaped//\"/\\\"}
escaped=${escaped//%/%%}
grep -Fqx "Exec=\"$escaped\" %u" "$WEIRD_HANDLER"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$WEIRD_HANDLER"
fi

echo 'deep-link handler test passed'
