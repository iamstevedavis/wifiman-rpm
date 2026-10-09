#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Exercise both installed wrapper locations, not just repository sourcing.
for mode in launcher daemon; do
  for scenario in regular saved atomic missing empty stale; do
    CASE_ROOT="$WORK_DIR/$mode/$scenario"
    APP_ROOT="$CASE_ROOT/usr/lib/wi-fiman-desktop"
    STATE_ROOT="$CASE_ROOT/state"
    RUNTIME_ROOT="$STATE_ROOT/app-root"
    mkdir -p "$APP_ROOT" "$RUNTIME_ROOT" "$CASE_ROOT/usr/bin"
    install -m 0644 "$ROOT_DIR/scripts/wifiman-runtime.sh" "$APP_ROOT/wifiman-runtime.sh"
    if [[ "$mode" == launcher ]]; then
      binary=wi-fiman-desktop-bin
      wrapper="$CASE_ROOT/usr/bin/wifiman-desktop"
      install -m 0755 "$ROOT_DIR/scripts/wifiman-desktop-launcher.sh" "$wrapper"
    else
      binary=wifiman-desktopd
      wrapper="$APP_ROOT/wifiman-desktopd-wrapper"
      install -m 0755 "$ROOT_DIR/scripts/wifiman-desktopd-wrapper.sh" "$wrapper"
    fi
    cat > "$APP_ROOT/$binary" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat service.json > "$STATE_ROOT/observed.json"
printf '%s\n' "$@" > "$STATE_ROOT/args.txt"
printf '%s\n' "$LOG_DIR" "$LOG_PATH" > "$STATE_ROOT/log-paths.txt"
EOF
    chmod +x "$APP_ROOT/$binary"
    # The daemon must not mirror the UI binary or treat arguments as items.
    if [[ "$mode" == daemon ]]; then
      touch "$APP_ROOT/wi-fiman-desktop-bin"
    fi
    touch "$APP_ROOT/--verbose" "$APP_ROOT/two words"
    touch "$RUNTIME_ROOT/.stale" "$RUNTIME_ROOT/junk.rpm" "$STATE_ROOT/service.json.tmp"
    printf '{"saved":true}\n' > "$CASE_ROOT/expected.json"
    case "$scenario" in
      regular)
        cp "$CASE_ROOT/expected.json" "$STATE_ROOT/service.json"
        ;;
      saved|atomic|missing|empty)
        ln -s "$RUNTIME_ROOT/service.json" "$STATE_ROOT/service.json"
        if [[ "$scenario" == saved ]]; then
          cp "$CASE_ROOT/expected.json" "$RUNTIME_ROOT/service.json"
        elif [[ "$scenario" == atomic ]]; then
          printf '{}\n' > "$RUNTIME_ROOT/service.json"
          cp "$CASE_ROOT/expected.json" "$RUNTIME_ROOT/service.json.tmp"
          mv "$RUNTIME_ROOT/service.json.tmp" "$RUNTIME_ROOT/service.json"
        else
          [[ "$scenario" != empty ]] || touch "$RUNTIME_ROOT/service.json"
          printf '{}\n' > "$CASE_ROOT/expected.json"
        fi
        ;;
      stale)
        ln -s "$CASE_ROOT/missing.json" "$STATE_ROOT/service.json"
        printf '{}\n' > "$CASE_ROOT/expected.json"
        ;;
    esac

    APP_ROOT="$APP_ROOT" STATE_ROOT="$STATE_ROOT" "$wrapper" --verbose 'two words'
    cmp "$CASE_ROOT/expected.json" "$STATE_ROOT/observed.json"
    cmp "$CASE_ROOT/expected.json" "$STATE_ROOT/service.json"
    test -L "$STATE_ROOT/service.json"
    test "$(readlink "$STATE_ROOT/service.json")" = "$RUNTIME_ROOT/service.json"
    printf '%s\n' --verbose 'two words' > "$CASE_ROOT/expected-args.txt"
    cmp "$CASE_ROOT/expected-args.txt" "$STATE_ROOT/args.txt"
    printf '%s\n' "$STATE_ROOT" "$STATE_ROOT/wifiman-desktop.log" > "$CASE_ROOT/expected-logs.txt"
    cmp "$CASE_ROOT/expected-logs.txt" "$STATE_ROOT/log-paths.txt"
    for excluded in .stale junk.rpm wifiman-runtime.sh --verbose 'two words'; do
      test ! -e "$RUNTIME_ROOT/$excluded"
    done
    test ! -e "$STATE_ROOT/service.json.tmp"
    if [[ "$mode" == daemon ]]; then
      test ! -e "$RUNTIME_ROOT/wi-fiman-desktop-bin"
    fi
  done
done

# The sourced helper must be supplied, installed and owned by the RPM.
grep -qx 'Source6:        wifiman-runtime.sh' "$ROOT_DIR/wifiman-desktop.spec"
grep -qx 'install -m 0644 %{SOURCE6} %{buildroot}%{_prefix}/lib/wi-fiman-desktop/wifiman-runtime.sh' "$ROOT_DIR/wifiman-desktop.spec"
grep -qx '%{_prefix}/lib/wi-fiman-desktop/wifiman-runtime.sh' "$ROOT_DIR/wifiman-desktop.spec"
grep -Fqx 'cp "$ROOT_DIR/scripts/wifiman-runtime.sh" "$TOPDIR/SOURCES/"' "$ROOT_DIR/scripts/build-rpm-from-stage.sh"

echo "shared runtime setup tests passed"
