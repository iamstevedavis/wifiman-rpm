#!/usr/bin/bash
set -euo pipefail

APP_ROOT=${APP_ROOT:-/usr/lib/wi-fiman-desktop}

# Desktop launches must use per-user writable state rather than /var/lib.
if [[ -z ${STATE_ROOT:-} ]]; then
  if [[ -n ${XDG_STATE_HOME:-} ]]; then
    STATE_ROOT="$XDG_STATE_HOME/wifiman-desktop"
  elif [[ -n ${HOME:-} ]]; then
    STATE_ROOT="$HOME/.local/state/wifiman-desktop"
  else
    STATE_ROOT=/tmp/wifiman-desktop
  fi
fi
RUNTIME_ROOT="$STATE_ROOT/app-root"

# The Tauri deep-link plugin registers its own handler on first run. Its Exec
# points at the raw UI binary (the current executable), which skips this
# launcher's per-user state and runtime mirror setup and cannot start the app.
# The handler name is derived from the executable basename, so install our own handler
# under that exact name before the app starts. The app checks only whether the
# scheme's default handler has that name and then leaves the file alone.
DEEP_LINK_SCHEME=x-scheme-handler/wifiman-desktop-dl
UI_BINARY_NAME=wi-fiman-desktop-bin
DEEP_LINK_HANDLER_NAME="$UI_BINARY_NAME-handler.desktop"

# Escape a path for a double-quoted Exec= value in a desktop entry. Backslash,
# backtick, dollar and double quote are special inside quotes, and percent
# starts a field code.
desktop_exec_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\`/\\\`}
  value=${value//\$/\\\$}
  value=${value//\"/\\\"}
  value=${value//%/%%}
  printf '%s' "$value"
}

ensure_deep_link_handler() {
  local data_home apps_dir handler launcher_path exec_path tmp current

  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    data_home=$XDG_DATA_HOME
  elif [[ -n ${HOME:-} ]]; then
    data_home="$HOME/.local/share"
  else
    return 0
  fi

  apps_dir="$data_home/applications"
  handler="$apps_dir/$DEEP_LINK_HANDLER_NAME"
  launcher_path=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
  [[ -n "$launcher_path" ]] || launcher_path=${BASH_SOURCE[0]}
  exec_path=$(desktop_exec_quote "$launcher_path")

  mkdir -p "$apps_dir" 2>/dev/null || return 0
  tmp=$(mktemp "$apps_dir/.wifiman-deep-link.XXXXXX" 2>/dev/null) || return 0

  if ! cat > "$tmp" <<EOF
[Desktop Entry]
Type=Application
Name=WiFiman Desktop
Comment=Discover devices and access Teleport VPNs
Exec="$exec_path" %u
Icon=wifiman-desktop
Terminal=false
NoDisplay=true
MimeType=$DEEP_LINK_SCHEME;
EOF
  then
    rm -f "$tmp"
    return 0
  fi
  if ! chmod 0644 "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  if [[ -f "$handler" ]] && cmp -s "$tmp" "$handler"; then
    rm -f "$tmp"
  elif ! mv -f "$tmp" "$handler"; then
    rm -f "$tmp"
    return 0
  fi

  # The plugin overwrites the association with xdg-mime default. Point it at
  # the managed handler instead so the app sees itself as already registered.
  if command -v xdg-mime >/dev/null 2>&1; then
    current=$(xdg-mime query default "$DEEP_LINK_SCHEME" 2>/dev/null || true)
    if [[ "$current" != "$DEEP_LINK_HANDLER_NAME" ]]; then
      xdg-mime default "$DEEP_LINK_HANDLER_NAME" "$DEEP_LINK_SCHEME" >/dev/null 2>&1 || true
    fi
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  fi
}

# In the RPM the launcher lives in /usr/bin, separate from the helper.
runtime_helper="$(dirname -- "${BASH_SOURCE[0]}")/wifiman-runtime.sh"
if [[ ! -f "$runtime_helper" ]]; then
  runtime_helper="$APP_ROOT/wifiman-runtime.sh"
fi
RUNTIME_EXTRA_ITEMS=("$UI_BINARY_NAME")
source "$runtime_helper"

# Upstream 1.3.0 links against the host WebKitGTK 4.1 / libsoup3 stack, so no
# loader or WebKit helper overrides are needed any more.

ensure_deep_link_handler

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/$UI_BINARY_NAME" "$@"
