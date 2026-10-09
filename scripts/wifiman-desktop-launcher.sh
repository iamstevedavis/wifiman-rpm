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

# Keep the runtime mirror intentionally selective. Mirroring the whole packaged
# tree previously pulled in junk artifacts and caused UI regressions.
RUNTIME_ITEMS=(
  .env
  .env.development
  .env.staging
  compat
  wg
  wg-quick
  wg_report.sh
  wi-fiman-desktop-bin
  wifiman-desktopd
  wireguard-go
)

mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT"

sync_runtime_item() {
  local name=$1
  local src="$APP_ROOT/$name"
  local dst="$RUNTIME_ROOT/$name"

  [[ -e "$src" ]] || return 0

  rm -rf "$dst"
  if [[ -d "$src" ]]; then
    cp -a "$src" "$dst"
  else
    install -D -m 0755 /dev/null "$dst"
    cp -a "$src" "$dst"
  fi
}

# If the state file already points at the runtime copy from a prior run, the
# config is already in the right place — preserve it. Only reseed when the
# symlink is broken or the runtime copy is missing.
if [[ -L "$STATE_ROOT/service.json" ]]; then
  target=$(readlink -f "$STATE_ROOT/service.json" || true)
  runtime_service=$(readlink -f "$RUNTIME_ROOT/service.json" 2>/dev/null || true)
  if [[ -n "$target" && "$target" == "$runtime_service" ]]; then
    # Symlink is valid and points at the runtime copy. Ensure the runtime
    # copy exists (it may have been cleaned) but do NOT reseed — the existing
    # config must survive.
    if [[ ! -s "$RUNTIME_ROOT/service.json" ]]; then
      printf '{}\n' > "$RUNTIME_ROOT/service.json"
    fi
    # Skip the reseed + copy below; the symlink already links state → runtime.
    skip_service_sync=1
  else
    # Symlink is stale or points elsewhere — break it so we can reseed.
    rm -f "$STATE_ROOT/service.json"
  fi
fi

if [[ ${skip_service_sync:-0} -eq 0 ]]; then
  if [[ ! -s "$STATE_ROOT/service.json" ]]; then
    printf '{}\n' > "$STATE_ROOT/service.json"
  fi
fi

shopt -s dotglob nullglob
# Clean stale runtime entries on each launch so old packaged artifacts do not
# linger after wrapper changes.
for existing in "$RUNTIME_ROOT"/*; do
  name=${existing##*/}
  if [[ "$name" == "service.json" ]]; then
    continue
  fi
  rm -rf "$existing"
done

for name in "${RUNTIME_ITEMS[@]}"; do
  sync_runtime_item "$name"
done

# Preserve service.json across runs, but avoid copying when source and target
# already match. When the symlink is already valid (skip_service_sync), the
# state file IS the runtime file — no copy or relink needed.
if [[ ${skip_service_sync:-0} -eq 0 ]]; then
  if [[ ! -e "$RUNTIME_ROOT/service.json" ]] || ! cmp -s "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"; then
    cp -f "$STATE_ROOT/service.json" "$RUNTIME_ROOT/service.json"
  fi
  ln -sfn "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
fi
rm -f "$STATE_ROOT/service.json.tmp"

export LOG_DIR="$STATE_ROOT"
export LOG_PATH="$STATE_ROOT/wifiman-desktop.log"

# Match the staged wrapper's compatibility-runtime exports. The upstream
# binary still needs the bundled WebKitGTK 4.0 / libsoup2 stack, so point
# the loader and WebKit helper lookup at the mirrored compat tree.
# WEBKIT_FORCE_SANDBOX is deliberately not copied from the staged wrapper;
# sandbox settings get their own review.
export LD_LIBRARY_PATH="$RUNTIME_ROOT/compat/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_EXEC_PATH="$RUNTIME_ROOT/compat/libexec/webkit2gtk-4.0"
export WEBKIT_INJECTED_BUNDLE_PATH="$RUNTIME_ROOT/compat/lib64/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so"

cd "$RUNTIME_ROOT"
exec "$RUNTIME_ROOT/wi-fiman-desktop-bin" "$@"
