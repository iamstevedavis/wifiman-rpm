#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"

workflows=(
  "$WORKFLOW_DIR/release.yml"
  "$WORKFLOW_DIR/test.yml"
)

for workflow in "${workflows[@]}"; do
  test -f "$workflow"
done

# Dependency-free regression check: a heredoc body inside a `run: |` block
# must stay indented in the YAML source. A column-0 line there silently ends
# the block scalar and invalidates the workflow (this happened in the 1.3.0
# release notes block).
python3 - "${workflows[@]}" <<'PY'
import re
import sys

errors = []
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        match = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
        if not match:
            index += 1
            continue

        terminator = match.group(1)
        base_indent = len(line) - len(line.lstrip(" "))
        end = index + 1
        closed = False
        while end < len(lines):
            content = lines[end]
            if content.strip() == terminator:
                closed = True
                break
            if content.strip():
                indent = len(content) - len(content.lstrip(" "))
                if indent < base_indent:
                    errors.append(
                        f"{path}:{end + 1}: heredoc content is less indented than "
                        f"line {index + 1} ({base_indent} spaces): {content!r}"
                    )
            end += 1
        if not closed:
            errors.append(f"{path}:{index + 1}: heredoc {terminator} is never closed")
        index = end + 1

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY

if python3 -c 'import yaml' >/dev/null 2>&1; then
  for workflow in "${workflows[@]}"; do
    python3 - "$workflow" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
if not isinstance(data, dict):
    raise SystemExit(f"{path}: expected a mapping at the top level")
# YAML 1.1 parsers turn the unquoted `on` key into boolean True.
if "on" not in data and True not in data:
    raise SystemExit(f"{path}: missing top-level 'on' trigger")
PY
  done
  echo "workflow YAML test passed (parsed with PyYAML)"
else
  echo "workflow YAML test passed (heredoc indentation check; PyYAML unavailable)"
fi
