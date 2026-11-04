#!/usr/bin/env python3
"""Disable the in-app updater prompt in the packaged WiFiman Desktop binary.

WiFiman Desktop 1.2.10 and 1.3.0 ship a Tauri frontend that checks for updates
by fetching ``wifiman-desktop-<platform>-manifest.json`` from the early-access
CDN at ``https://desktop.ea.wifiman.com``.  The request is gated by the
``tauri-plugin-http`` scope compiled into the app binary.

Rewriting that one scope entry to a non-matching host makes the request fail
locally, so the UI never offers an upstream ``.deb`` over the package-managed
tree.  The replacement is the same length as the original so the binary layout
and every other offset stay unchanged.  The host uses the RFC 2606 reserved
``.invalid`` TLD, so it can never resolve.
"""

from __future__ import annotations

import os
import stat
import sys
import tempfile
from pathlib import Path

OLD_SCOPE = b"https://desktop.ea.wifiman.com/*"
NEW_SCOPE = b"https://updater-block9.invalid/*"


def write_atomically(path: Path, data: bytes) -> None:
    """Replace ``path`` with ``data`` without truncating the original in place."""
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as tmp:
            tmp.write(data)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    args = sys.argv[1:]
    check_only = bool(args and args[0] == "--check")
    if check_only:
        args = args[1:]

    if len(args) != 1:
        print(
            f"usage: {Path(sys.argv[0]).name} [--check] <wifiman-desktop-binary>",
            file=sys.stderr,
        )
        return 2

    path = Path(args[0])
    data = bytearray(path.read_bytes())
    old_count = data.count(OLD_SCOPE)
    new_count = data.count(NEW_SCOPE)

    if check_only:
        if old_count == 1 and new_count == 0:
            print(f"{path}: updater scope is unpatched (exactly one entry)")
            return 0
        if old_count == 0 and new_count == 1:
            print(f"{path}: updater scope is patched")
            return 0
        print(
            f"error: expected exactly one patched or unpatched updater scope entry "
            f"in {path}, found old={old_count} new={new_count}",
            file=sys.stderr,
        )
        return 1

    # Staging copies a fresh upstream payload before calling this, so a second
    # run against the same file is not expected.  Treat an already-patched or
    # unexpectedly shaped binary as an error rather than silently shipping it.
    if old_count != 1:
        print(
            f"error: expected exactly one updater scope entry in {path}, found {old_count}",
            file=sys.stderr,
        )
        return 1

    if len(OLD_SCOPE) != len(NEW_SCOPE):
        raise AssertionError("replacement scope must keep the original length")

    offset = data.find(OLD_SCOPE)
    data[offset : offset + len(OLD_SCOPE)] = NEW_SCOPE
    write_atomically(path, data)
    print(f"disabled in-app updater scope in {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
