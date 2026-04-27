# WiFiman Desktop RPM for newer Fedora

This repo packages upstream **WiFiman Desktop 1.1.2** for newer Fedora releases.

The upstream app still depends on the older WebKitGTK 4.0 / libsoup2 runtime stack, so this package stages a private compatibility runtime and wraps the app with the right environment.

## What this repo does

- downloads upstream `wifiman-desktop-1.1.2-amd64.deb`
- extracts the app payload
- pulls Fedora 40 compatibility libraries for the older WebKitGTK 4.0 stack
- stages a runnable app tree with a wrapper
- builds an RPM from that staged tree

## Requirements

On Fedora:

```bash
sudo dnf install -y docker git
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
./scripts/stage-wifiman-1.1.2-fedora-newer.sh
```

### 2) Verify library resolution locally

```bash
./scripts/verify-fedora-newer-stage.sh
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

## Install the built RPM on Fedora

Adjust the exact filename if the release changes:

```bash
sudo dnf install ./.rpmbuild/RPMS/x86_64/wifiman-desktop-1.1.2-1*.rpm
```

Then enable the daemon:

```bash
sudo systemctl enable --now wifiman-desktop.service
```

Launch the app:

```bash
wi-fiman-desktop
```

## Notes

- this packaging path currently targets `x86_64`
- the build uses Docker internally
- on SELinux-enforcing Fedora hosts, the RPM build container bind mount is labeled with `:Z`
- host EGL / GLVND pieces are expected from the Fedora system rather than fully bundled into the compat runtime

## Repo status

This repo is focused on the local newer-Fedora packaging path and the direct build/test/install flow for Fedora.
