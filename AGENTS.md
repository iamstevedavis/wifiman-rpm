# AGENTS.md

Guidance for AI agents and automation working in this repo.

## Purpose

This repo packages upstream WiFiman Desktop for newer Fedora releases and carries local wrapper / SELinux workarounds needed to keep the app and daemon usable.

## High-level rules

- Prefer small, surgical changes.
- Preserve working UI behavior before chasing new daemon / SELinux fixes.
- Any change that affects launcher, daemon wrapper, runtime state, or SELinux flow must include or update tests.
- If you change the repo on a remote/VPS for someone testing locally, **push before telling them to test**.

## Repo workflow

Before proposing a test to a human on another machine:

1. run the local test suite
2. commit the change
3. push the branch they will pull from

Minimum loop:

```bash
./tests/run-all.sh
git add <files>
git commit -m "..."
git push
```

## Testing expectations

Primary local regression suite:

```bash
./tests/run-all.sh
```

Current coverage focuses on:

- launcher uses per-user state
- launcher honors `XDG_STATE_HOME`
- daemon wrapper handles reruns/idempotency
- runtime mirror excludes junk artifacts that broke the UI
- runtime mirror cleans stale entries
- SELinux installer structure + mocked execution

If you fix a regression that was discovered manually, add a test that would have caught it.

## Runtime mirror rules

The runtime mirror under state is intentionally selective.

Do **not** go back to mirroring everything from `/usr/lib/wi-fiman-desktop`.

Reasons:

- it can pull package artifacts into runtime state
- it previously broke UI behavior
- it can reintroduce permission and same-file bugs

Only explicitly required runtime items should be mirrored.

## State path rules

- Desktop launcher: per-user writable state (`XDG_STATE_HOME` or `~/.local/state`)
- System daemon: `/var/lib/wifiman-desktop`

Do not collapse these into one default path.

## SELinux guidance

Treat SELinux changes as high-risk.

- First confirm the failure is not caused by packaging/wrapper logic.
- Avoid “fixing” SELinux by broadening policy before reproducing on a clean package state.
- Keep SELinux tests and packaging/UI tests separate in your reasoning.

## Documentation upkeep

If workflows change, update:

- `README.md`
- `.github/workflows/release.yml`
- test runner references

Keep instructions copy-pasteable. Prefer one-line commands when giving commands to a human tester.
