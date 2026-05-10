# WiFiman Desktop RPM for newer Fedora

This repo packages upstream **WiFiman Desktop 1.2.10** for newer Fedora releases.

The upstream app still depends on the older WebKitGTK 4.0 / libsoup2 runtime stack, so this package stages a private compatibility runtime and wraps the app with the right environment. When the upstream payload still includes its `.env`, the RPM build also suppresses the built-in updater prompt by stretching the packaged updater timing values.

## Install the release RPM on Fedora

Most users should install the prebuilt release RPM instead of building from source.

1. Download the latest `wifiman-desktop-*-x86_64.rpm` from the [GitHub Releases page](https://github.com/iamstevedavis/wifiman-rpm/releases).
2. Install it with DNF:

```bash
sudo dnf install ./wifiman-desktop-1.2.10-1.fc40.x86_64.rpm
```

3. Launch it from KDE / your Applications menu as **WiFiman Desktop**, or from a terminal:

```bash
wifiman-desktop
```

The package also installs and enables support files for the background daemon. If the daemon is blocked on SELinux-enforcing Fedora, see [SELinux policy helper](#selinux-policy-helper).

## What this repo does

- downloads upstream `wifiman-desktop-1.2.10-amd64.deb`
- extracts the app payload
- pulls Fedora 40 compatibility libraries for the older WebKitGTK 4.0 stack
- stages a runnable app tree with a wrapper
- builds an RPM from that staged tree

## Requirements

On Fedora:

```bash
sudo dnf install -y docker git policycoreutils-python-utils setools-console
sudo systemctl enable --now docker
```

Your user also needs Docker access:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## Quick build

From the repo root:

```bash
./scripts/build-rpm-from-stage.sh
```

That script now:

1. rebuilds the stage by default
2. validates the required staged files exist
3. builds the RPM in a Fedora 40 container

Artifacts are written to:

```bash
./.rpmbuild/RPMS
./.rpmbuild/SRPMS
```

## Step-by-step build and test

### 1) Build the staged app tree

```bash
./scripts/stage-wifiman-fedora-newer.sh
# defaults to upstream 1.2.10 unless UPSTREAM_VERSION is overridden
```

### 2) Verify library resolution locally

```bash
./scripts/verify-fedora-newer-stage.sh
```

### 2.5) Run the local test suite

```bash
./tests/run-all.sh
```

### 3) Test against a Fedora container

```bash
./scripts/test-fedora-newer-stage-in-container.sh
```

### 4) Build the RPM

```bash
./scripts/build-rpm-from-stage.sh
```

### 5) Inspect the artifacts

```bash
find ./.rpmbuild/RPMS ./.rpmbuild/SRPMS -type f | sort
```


## Release builds

The GitHub Actions release workflow builds versioned RPM artifacts and publishes them as downloadable assets.

- Push a tag like `v1.2.10` to create/update the matching GitHub release.
- Or run the **release** workflow manually with `version`, `rpm_release`, and `create_release=true`.

The workflow uploads:

- binary RPM from `.rpmbuild/RPMS`
- source RPM from `.rpmbuild/SRPMS`
- SHA256 checksum file

## Clean removal / install helper scripts

For a clean local reinstall, remove the package, service, and runtime state:

```bash
./scripts/remove-wifiman-desktop.sh
```

By default this removes `/var/lib/wifiman-desktop` and the current user's WiFiman state under `${XDG_STATE_HOME:-~/.local/state}`. It keeps local SELinux modules unless explicitly requested:

```bash
REMOVE_SELINUX_MODULES=1 ./scripts/remove-wifiman-desktop.sh
```

Build, install, and start the service in one command:

```bash
./scripts/install-and-run-wifiman-desktop.sh
```

Useful overrides:

```bash
RPM_PATH=/path/to/wifiman-desktop.rpm BUILD_RPM=0 ./scripts/install-and-run-wifiman-desktop.sh
INSTALL_SELINUX_POLICY=1 ./scripts/install-and-run-wifiman-desktop.sh
LAUNCH_APP=1 ./scripts/install-and-run-wifiman-desktop.sh
DNF_REFRESH=0 ./scripts/install-and-run-wifiman-desktop.sh
DNF_CLEAN_METADATA=0 ./scripts/install-and-run-wifiman-desktop.sh
```

Collect diagnostics to paste into an issue/chat:

```bash
./scripts/collect-wifiman-debug-logs.sh
```

The log bundle is written to `/tmp/wifiman-debug.log` by default.

## SELinux policy helper

The upstream daemon uses raw ICMP / raw socket operations for device discovery and related networking behavior. On Fedora with SELinux enforcing, that can trigger denials until a local policy module is installed.

This package now seeds a minimal valid `service.json` so the daemon does not crash on first run due to an empty config file, redirects logs into `/var/lib/wifiman-desktop`, and runs from a writable runtime mirror so upstream writes to `service.json(.tmp)` land under `/var/lib/wifiman-desktop` instead of the packaged `/usr/lib/wi-fiman-desktop` tree.

Enable the daemon once so SELinux has something to audit:

```bash
sudo systemctl enable --now wifiman-desktop.service
```

If SELinux blocks the daemon, install the bundled local policy module and merge in any recent AVC-based deltas:

```bash
./scripts/install-selinux-policy.sh
```

That helper is only needed when SELinux is enforcing and the daemon gets denied. It:

- re-runs itself with `sudo` when needed
- compiles the repo-managed base policy from `scripts/wifiman-desktop.te`
- installs that policy as the `wifiman-desktop` SELinux module with priority `300`
- checks recent audit logs for `wifiman-desktop` AVC denials
- optionally generates and installs a second local AVC-derived module, `wifiman_desktop_local`, when `ausearch`/`audit2allow` find useful denials
- restarts `wifiman-desktop.service`
- prints the resulting service status

The helper does not change SELinux mode and does not disable enforcement. It adds local allow rules for this packaged daemon.

If you need a wider audit window, you can override the time filter:

```bash
SINCE=boot ./scripts/install-selinux-policy.sh
```

## Notes

- this packaging path currently targets `x86_64`
- the build uses Docker internally
- on SELinux-enforcing Fedora hosts, the RPM build container bind mount is labeled with `:Z`
- host EGL / GLVND pieces are expected from the Fedora system rather than fully bundled into the compat runtime
- the RPM also installs the WebKit injected bundle into the system `webkit2gtk-4.0` path expected by the upstream app
- the daemon SELinux policy helper now includes a repo-managed base policy plus optional local AVC-derived deltas; it is still a local-machine workaround, not an upstream Fedora policy integration yet

## Agent / automation notes

Repo-local guidance for AI agents and automation lives in `AGENTS.md`.

## Repo status

This repo is focused on the local newer-Fedora packaging path and the direct build/test/install flow for Fedora.

## Repo layout

- `scripts/` — build, staging, wrapper, and SELinux helper scripts
- `tests/` — local regression tests and the `run-all.sh` test runner
- `wifiman-desktop.spec` — RPM spec file
- `FEDORA_NEWER_NOTES.md` — extra packaging notes and context
- `AGENTS.md` — repo-specific guidance for AI agents and automation
