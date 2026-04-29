#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/scripts/stage-wifiman-fedora-newer.sh"

bash -n "$SCRIPT"

grep -q 'LOG_LEVEL=debug' "$SCRIPT"
grep -q 'UPDATER_DELAY=31536000000' "$SCRIPT"
grep -q 'UPDATER_INTERVAL=31536000000' "$SCRIPT"

python3 - <<'PY' "$SCRIPT"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert '"# LOG_LEVEL=debug": "LOG_LEVEL=debug"' in text
assert '"UPDATER_DELAY=120000": "UPDATER_DELAY=31536000000"' in text
assert '"UPDATER_INTERVAL=43200000": "UPDATER_INTERVAL=31536000000"' in text
print('stage env patch test passed')
PY
