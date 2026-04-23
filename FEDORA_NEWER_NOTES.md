# WiFiman Desktop on newer Fedora

## Summary

The repo currently packages WiFiman Desktop `0.3.0`, but upstream WiFiman Desktop has moved to `1.1.x` with a different Debian package layout.

An existing open PR already adapts the spec to the new `1.1.x` package layout:

- https://github.com/abn/wifiman-desktop-rpm/pull/2

However, testing shows that this is not enough for newer Fedora releases.

## Verified runtime breakage

The upstream `1.1.x` launcher binary links against:

- `libwebkit2gtk-4.0.so.37`
- `libsoup-2.4.so.1`
- `libjavascriptcoregtk-4.0.so.18`

On newer Fedora (for example Fedora 43), those are no longer present by default because Fedora moved to newer WebKitGTK / libsoup ABI packages.

`ldd` against the upstream `wi-fiman-desktop` binary on current Fedora showed unresolved libraries including:

- `libwebkit2gtk-4.0.so.37`
- `libsoup-2.4.so.1`
- `libjavascriptcoregtk-4.0.so.18`

After injecting Fedora 40 compatibility libs, more transitive runtime requirements still remained, including examples like:

- ICU 74 (`libicui18n.so.74`, `libicuuc.so.74`)
- `libxslt.so.1`
- `libwoff2dec.so.1.0.2`
- `libgsttranscoder-1.0.so.0`
- `libjxl.so.0.8`
- `libavif.so.16`
- `libharfbuzz-icu.so.0`
- `libenchant-2.so.2`
- `libsecret-1.so.0`
- `libwayland-server.so.0`
- `libmanette-0.2.so.0`
- `libatomic.so.1`

So the problem is not just the specfile. The upstream app binary is tied to an older runtime stack.

## Practical packaging options

### Option 1: bundle compatibility runtime in the RPM

Bundle the required Fedora-40-era runtime libraries under an app-private path such as:

- `/opt/wifiman-desktop/compat/lib64`

Then ship a wrapper script that launches the upstream binary with something like:

```bash
export LD_LIBRARY_PATH=/opt/wifiman-desktop/compat/lib64:${LD_LIBRARY_PATH}
exec /opt/wifiman-desktop/bin/wi-fiman-desktop "$@"
```

Pros:
- Most likely to work on newer Fedora
- Keeps install local to the package

Cons:
- Larger RPM
- More maintenance
- Needs careful selection of bundled libs to avoid conflicts
- COPR policy/packaging expectations may make this awkward

### Option 2: target older Fedora only

Only support Fedora versions that still ship WebKitGTK 4.0 / libsoup2 ABI natively.

Pros:
- Simpler spec

Cons:
- Does not solve the user's newer Fedora case

### Option 3: use a more self-contained format

Move away from a thin RPM wrapper around the upstream Debian package and instead use:

- AppImage-style repackaging
- Flatpak-style packaging
- custom installer/runtime bundle

Pros:
- Better fit for legacy runtime compatibility

Cons:
- Bigger change from current repo structure

## Recommendation

For newer Fedora, the most realistic fix is:

1. start from PR #2 for the new `1.1.x` file layout
2. add an app-private compatibility runtime bundle
3. replace direct binary execution with a small launcher wrapper
4. verify with `ldd` and an actual test launch on the target Fedora release

## Notes gathered during investigation

- `desktop.ea.wifiman.com/wifiman-desktop-1.1.0-amd64.deb` and `1.1.2` are still downloadable
- The old stable `desktop.wifiman.com/wifiman-desktop-1.1.0-linux-amd64.deb` path returned `403`
- Fedora 43 still has `webkit2gtk4.1`, but not `webkit2gtk4.0`
- Fedora 40 still has `webkit2gtk4.0`, `libsoup`, and `libappindicator-gtk3`
