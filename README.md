[![Copr Build Status](https://copr.fedorainfracloud.org/coprs/abn/wifiman-desktop/package/wifiman-desktop/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/abn/wifiman-desktop/)

# RPM Package: wifiman-desktop

This repository holds the RPM package source for [wifiman-desktop](https://www.ui.com/download/app/wifiman-desktop).

## Status

The original packaging in this repo targets the old `0.3.0` Debian layout. Current WiFiman Desktop (`1.1.x`) changed layout, binary names, and runtime dependencies.

On newer Fedora releases, the upstream `1.1.x` binary also depends on the older WebKitGTK 4.0 / libsoup2 stack (`libwebkit2gtk-4.0.so.37`, `libsoup-2.4.so.1`, `libjavascriptcoregtk-4.0.so.18`), while newer Fedora releases have moved on to newer WebKitGTK ABI packages. That means a straight spec bump is not enough for current Fedora.

> WiFiman is here to save your home or office network from sluggish surfing, endless buffering, and congested data 
> channels.

> [!NOTE]  
> This is a wrapper package of the WiFiman Desktop releases for Ubuntu available [here](https://www.ui.com/download/app/wifiman-desktop)
> and is in no way affliated with or maintained by [Ubiquity Inc](https://ui.com/) for any application support or questions please see
> [here](https://help.ui.com/hc/en-us).


## Current findings for newer Fedora

- Current upstream repo state is still on `0.3.0`
- There is an open PR for `1.1.x`: <https://github.com/abn/wifiman-desktop-rpm/pull/2>
- That PR fixes the new Debian package layout, but it is not sufficient for current Fedora releases by itself
- Verified breakage on newer Fedora comes from missing older WebKitGTK 4.0 / libsoup2 ABI required by upstream WiFiman Desktop `1.1.x`

## What needs to change

For newer Fedora, this package likely needs one of these approaches:

1. Bundle a private compatibility runtime for the older WebKitGTK 4.0 / libsoup2 stack and launch WiFiman with an app-local `LD_LIBRARY_PATH`
2. Target an older Fedora base where those ABI packages still exist natively
3. Replace the RPM approach with a more self-contained packaging format (for example AppImage/Flatpak-style packaging)

## Local Fedora-newer path in this repo

This repo now includes a local compatibility-staging path for newer Fedora releases:

- `scripts/fetch-fedora40-compat-libs.sh`
- `scripts/stage-wifiman-1.1.2-fedora-newer.sh`
- `scripts/wi-fiman-desktop-wrapper.sh`

What it does:

1. downloads upstream WiFiman Desktop `1.1.2`
2. extracts the Debian package payload
3. downloads Fedora 40 compatibility RPMs for the older WebKitGTK 4.0 / libsoup2 stack
4. extracts only the private runtime libraries needed for the app
5. stages a local runnable tree with a wrapper that sets `LD_LIBRARY_PATH`

Default stage output:

```sh
./out/wifiman-desktop-fedora-newer
```

Example:

```sh
./scripts/stage-wifiman-1.1.2-fedora-newer.sh
./out/wifiman-desktop-fedora-newer/bin/wi-fiman-desktop
```

Verification:

```sh
./scripts/verify-fedora-newer-stage.sh
./scripts/test-fedora-newer-stage-in-container.sh
```

Notes:

- this is meant as a pragmatic newer-Fedora compatibility path, not a polished COPR-ready spec yet
- it currently assumes `x86_64`
- it uses `docker` to fetch Fedora 40 runtime RPMs in a clean environment
- compat libraries are copied as real payload files into the stage tree so the wrapper can run independently of the cache directory
- current verification work reduced the unresolved runtime set to a single graphics-side dependency: `libEGL.so.1`
- in practice, EGL/GLVND is likely better treated as host-provided on Fedora rather than fully privatized in the compatibility bundle

## Usage
You can use this package by enabling the copr repository at [abn/wifiman-desktop](https://copr.fedorainfracloud.org/coprs/abn/wifiman-desktop/) as described [here](https://fedorahosted.org/copr/wiki/HowToEnableRepo).

```sh
dnf copr enable abn/wifiman-desktop
dnf install wifiman-desktop
```

Once installed you can enable and start the daemon using the following command, then launch the application.

```sh
systemctl enable --now wifiman-desktop.service
```
