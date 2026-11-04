#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PATCH="$ROOT_DIR/scripts/patch-wifiman-updater-scope.py"
STAGE="$ROOT_DIR/scripts/stage-wifiman-fedora-newer.sh"
OLD_SCOPE='https://desktop.ea.wifiman.com/*'
NEW_SCOPE='https://updater-block9.invalid/*'

bash -n "$STAGE"
grep -q 'patch-wifiman-updater-scope.py' "$STAGE"

# The replacement must keep the original length (the binary is patched in
# place) and use the RFC 2606 reserved .invalid TLD so it can never resolve.
[[ "${#NEW_SCOPE}" -eq "${#OLD_SCOPE}" ]]
[[ "$NEW_SCOPE" == *'.invalid/*' ]]
python3 - "$NEW_SCOPE" <<'PY'
import sys
from urllib.parse import urlparse

url = sys.argv[1]
host = urlparse(url).hostname
assert host and host.endswith(".invalid"), host
print("updater block host uses reserved .invalid TLD")
PY

# The old .env timing patch was a no-op for 1.2.10. The scope patch is the
# effective suppression and must stay wired into staging.
! grep -q 'UPDATER_DELAY=31536000000' "$STAGE"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fixture="$tmpdir/app"
printf 'prefix\0%s\0suffix' "$OLD_SCOPE" > "$fixture"
chmod 0751 "$fixture"
before=$(stat -c %s "$fixture")
before_mode=$(stat -c %a "$fixture")

python3 "$PATCH" --check "$fixture" >/dev/null
python3 "$PATCH" "$fixture" >/dev/null
python3 "$PATCH" --check "$fixture" >/dev/null

after=$(stat -c %s "$fixture")
after_mode=$(stat -c %a "$fixture")
[[ "$before" == "$after" ]]
[[ "$before_mode" == "$after_mode" ]]
grep -aqF "$NEW_SCOPE" "$fixture"
! grep -aqF "$OLD_SCOPE" "$fixture"

# A second patch run is not expected because staging recopies the upstream
# payload first.  It must fail rather than silently accepting the binary.
if python3 "$PATCH" "$fixture" >/dev/null 2>&1; then
  echo "expected patch to fail on an already-patched binary" >&2
  exit 1
fi

# Missing or duplicated scope entries must fail loudly instead of producing an
# unpatched or partially patched binary.
printf 'no updater scope here' > "$fixture"
if python3 "$PATCH" "$fixture" >/dev/null 2>&1; then
  echo "expected patch to fail when the updater scope is missing" >&2
  exit 1
fi

printf '%s\n%s\n' "$OLD_SCOPE" "$OLD_SCOPE" > "$fixture"
if python3 "$PATCH" "$fixture" >/dev/null 2>&1; then
  echo "expected patch to fail when the updater scope is duplicated" >&2
  exit 1
fi

echo 'stage updater scope patch test passed'
