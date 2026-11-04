#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

APP_ROOT="$WORK_DIR/app-root-src"
HOME_DIR="$WORK_DIR/home"
XDG_DATA_DIR="$WORK_DIR/data"
XDG_CONFIG_DIR="$WORK_DIR/config"
BIN_DIR="$WORK_DIR/bin"
mkdir -p "$APP_ROOT" "$HOME_DIR" "$XDG_DATA_DIR" "$XDG_CONFIG_DIR" "$BIN_DIR"

LAUNCHER="$ROOT_DIR/scripts/wifiman-desktop-launcher.sh"
HANDLER="$XDG_DATA_DIR/applications/wi-fiman-desktop-bin-handler.desktop"
SCHEME='x-scheme-handler/wifiman-desktop-dl'

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

run_launcher() {
  HOME="$HOME_DIR" \
  XDG_DATA_HOME="$XDG_DATA_DIR" \
  XDG_CONFIG_HOME="$XDG_CONFIG_DIR" \
  XDG_MIME_STATE="$WORK_DIR/mime-default" \
  XDG_MIME_LOG="$WORK_DIR/xdg-mime.log" \
  XDG_DESKTOP_DB_LOG="$WORK_DIR/desktop-db.log" \
  PATH="$BIN_DIR:$PATH" \
  APP_ROOT="$APP_ROOT" \
  bash "$LAUNCHER" "wifiman-desktop-dl://invite/test"
}

# A stale plugin handler points at the raw binary and has no Icon. The launcher
# must rewrite it to use the wrapper instead.
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
printf '%s\n' 'wi-fiman-desktop-bin-handler.desktop' > "$WORK_DIR/mime-default"
: > "$WORK_DIR/xdg-mime.log"
: > "$WORK_DIR/desktop-db.log"

run_launcher

grep -qx 'wifiman-desktop-dl://invite/test' "$HOME_DIR/deep-link-args.txt"
grep -Fqx "Exec=\"$LAUNCHER\" %u" "$HANDLER"
grep -qx "MimeType=$SCHEME;" "$HANDLER"
grep -qx 'Icon=wifiman-desktop' "$HANDLER"
grep -qx 'NoDisplay=true' "$HANDLER"
! grep -q '/usr/lib/wi-fiman-desktop/wi-fiman-desktop-bin' "$HANDLER"
grep -Fq "query default $SCHEME" "$WORK_DIR/xdg-mime.log"
# The default already used the managed handler name, so it was left alone.
! grep -Fq 'default wi-fiman-desktop-bin-handler.desktop' "$WORK_DIR/xdg-mime.log"
grep -Fqx "$XDG_DATA_DIR/applications" "$WORK_DIR/desktop-db.log"
test -z "$(find "$XDG_DATA_DIR/applications" -maxdepth 1 -name '.wifiman-deep-link.*' -print -quit)"

# With no handler and no default, the launcher must create the handler and
# point the scheme at it before the app has a chance to register its own.
rm -rf "$XDG_DATA_DIR/applications" "$HOME_DIR/deep-link-args.txt"
: > "$WORK_DIR/mime-default"
: > "$WORK_DIR/xdg-mime.log"
: > "$WORK_DIR/desktop-db.log"

run_launcher

grep -Fqx "Exec=\"$LAUNCHER\" %u" "$HANDLER"
grep -qx "MimeType=$SCHEME;" "$HANDLER"
grep -Fq "default wi-fiman-desktop-bin-handler.desktop $SCHEME" "$WORK_DIR/xdg-mime.log"
grep -qx 'wi-fiman-desktop-bin-handler.desktop' "$WORK_DIR/mime-default"

echo 'deep-link handler test passed'
