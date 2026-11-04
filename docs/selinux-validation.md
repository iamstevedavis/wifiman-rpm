# SELinux scope migration / issue #15

## Status

The dedicated daemon policy in `scripts/wifiman-desktop.te` is now the default
for `scripts/install-selinux-policy.sh`. It replaces the previous policy that
granted networking and generic file access to the shared `init_t` domain.

The legacy policy is retained as `scripts/wifiman-desktop-legacy.te` for an
explicit rollback and as the automatic fallback if the dedicated transition or
service start fails. `scripts/wifiman-desktop.fc` installs the label mappings.

The dedicated module:

- transitions only the systemd entry point
  `/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper` from `init_t` to
  `wifiman_t`
- grants networking to `wifiman_t` instead of the shared `init_t` domain
- replaces writes to generic `lib_t`, `var_lib_t`, and `init_var_lib_t` with
  WiFiman-specific `wifiman_lib_t` and `wifiman_var_t` object types
- labels copied helpers (`wifiman-desktopd`, `wireguard-go`, `wg`, `wg-quick`,
  `wg_report.sh`) as `wifiman_helper_exec_t`, keeping the writable state
  directory non-executable
- leaves the desktop UI in the user's domain; only the system daemon wrapper
  transitions

The installer relabels the packaged tree and the runtime mirror, then restarts
the service and verifies that the main PID runs as `wifiman_t`. It stops the
service before replacing the module or changing labels, because replacing the
module while a `wifiman_t` process is running would remove that type and leave
systemd unable to signal the process.

## Validation performed

Environment: Fedora 44 Cloud VM, kernel `6.19.10-300.fc44.x86_64`,
`selinux-policy-targeted-43.3-1.fc44`, `checkpolicy-3.11-1.fc44`,
`setools-console-4.6.0-6.fc44`, SELinux **enforcing**, RPM
`wifiman-desktop-1.2.10-2.fc40.x86_64`.

The live development host's policy was **not modified**. Testing was done in a
disposable VM. The module was also compiled and installed into a copy of the
host policy store in a container to check the real semantic link/expand path.

Results:

- Clean RPM install starts the daemon in `init_t` (legacy behavior).
- `WIFIMAN_SELINUX_POLICY=dedicated` installs the module and verifies the main
  PID runs as `wifiman_t`.
- `ps -eZ` shows `system_u:system_r:wifiman_t:s0`; the UI binary is not
  transitioned.
- Labels are as intended:
  - `/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper` -> `wifiman_exec_t`
  - packaged helpers -> `wifiman_helper_exec_t`
  - other packaged data and compatibility libraries -> `wifiman_lib_t`
  - `/var/lib/wifiman-desktop` and state files -> `wifiman_var_t`
  - runtime helper executables (including the MTU-patched `wg-quick`) ->
    `wifiman_helper_exec_t`
- The daemon's local API binds successfully on `127.0.0.1:63150` and listens.
  That port falls in Fedora's `mysqld_port_t` range (63132-63164), so the
  policy grants `name_bind` on `mysqld_port_t` as well as the general
  ephemeral/unreserved port ranges.
- `systemctl restart` and a full VM reboot both preserve the domain and labels;
  no `avc: denied` records for `wifiman_t` were observed during the final
  start/restart/reboot cycle.
- The WireGuard helper path was exercised under `wifiman_t` with a disposable
  test configuration: `wg-quick up` created the interface with the expected
  MTU cap (1280), and `wg-quick down` removed it, without an AVC. This used the
  kernel WireGuard implementation; the upstream `wireguard-go` userspace path
  is not yet exercised in a real VPN session.
- Switching dedicated -> legacy and legacy -> dedicated no longer leaves an
  unsignalable process behind; the installer stops the service before replacing
  the module.
- `./tests/run-all.sh` passes, including the dedicated-domain installer test,
  offline compilation of both policy sources, fallback behavior, and the
  existing installer/removal tests.

## Still required before closing issue #15

The remaining items need an interactive Fedora desktop and a real VPN/profile,
not just a headless VM:

1. Launch the UI, verify discovery against real UniFi devices, and exercise a
   real Teleport/VPN session, disconnect/reconnect, and a reboot with the UI
   running. Record `sudo ausearch -m AVC,USER_AVC -ts boot --raw`, the service
   journal, `ps -eZ`, and labels for the UI, daemon, helpers and state.
2. Exercise the `wireguard-go` userspace implementation (for hosts without the
   kernel module), not only kernel WireGuard.
3. Audit attempted writes to `/usr/lib/wi-fiman-desktop` during UI, discovery
   and VPN operations. Wrapper state redirection alone does not prove the
   opaque upstream daemon never writes an absolute packaged-tree path. Keep the
   legacy source until that audit is complete.
4. Review any new AVC-derived rules against the reproduced failure, including
   source/target types and permission scope. In dedicated mode, reject
   `init_t` rules; the daemon should be `wifiman_t`.
5. Confirm long-running discovery, reconnect and sleep/wake behavior does not
   accumulate denials, and attach the results to the completing PR.

## Legacy policy

`WIFIMAN_SELINUX_POLICY=legacy` still grants permissions to shared `init_t` and
generic `lib_t`/`var_lib_t`/`init_var_lib_t` labels. Its rules affect every
process in those domains; filtering audit records by `comm` does not narrow the
allow rules. The installer saves generated AVC rules for review rather than
installing them automatically. Supplying `REVIEWED_AVC_TE` explicitly
authorizes compiling and installing that source. Review previously installed
local modules separately; this workflow does not change them.

To roll back from dedicated mode:

```bash
sudo env WIFIMAN_SELINUX_POLICY=legacy ./scripts/install-selinux-policy.sh
```

The installer stops the service, replaces the module, restores default labels,
restarts the service, and reports the resulting status.
