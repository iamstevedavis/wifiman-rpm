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
  WiFiman-specific object types:
  - `wifiman_lib_t` for the packaged tree, which is **read-only** to the daemon
  - `wifiman_helper_exec_t` for packaged helper binaries (read-only)
  - `wifiman_runtime_exec_t` for copied runtime helpers (writable/executable)
  - `wifiman_var_t` for state and runtime-mirror data (writable, not executable)
- leaves the writable runtime mirror and state non-executable except for the
  explicitly named runtime helper files
- leaves the desktop UI in the user's domain; only the system daemon wrapper
  transitions

The installer relabels the packaged tree and the runtime mirror, then restarts
the service and verifies that the main PID runs as `wifiman_t`. It stops the
service before replacing the module or changing labels, because replacing the
module while a `wifiman_t` process is running would remove that type and leave
systemd unable to signal the process.

## Permission rationale

The remaining capability and process grants are intentionally small:

- `net_admin` and `net_raw` are required for TUN/interface setup, raw-socket
  discovery and WireGuard startup.
- `fork`, `signal`, `sigchld`, `sigkill`, `signull`, `sigstop`,
  `getattr`, `getpgid`, `getrlimit`, `getsched`, `setpgid`, `setrlimit` and
  `setsched` cover process management and the Go runtime. `noatsecure`,
  `rlimitinh` and `siginh` apply only to the `init_t` -> `wifiman_t`
  transition.
- There are no SELinux relabel grants. Copying does not preserve package
  contexts in dedicated mode (`cp -a --no-preserve=context`), and the MTU cap
  writes the patched content through the existing runtime `wg-quick` inode so
  it keeps `wifiman_runtime_exec_t` instead of creating a new inode.
- The daemon does not receive `dac_override`, `dac_read_search`, `setuid`,
  `setgid`, `net_bind_service`, `sys_nice`, `sys_resource`, `ipc_lock`,
  `ipc_owner`, `kill`, `setexec`, `setcurrent`, `setfscreate`,
  `setkeycreate`, `setsockcreate`, `setcap` or `getcap`.

The local API port `127.0.0.1:63150` falls inside Fedora's `mysqld_port_t`
range, so the policy needs that one named port type in addition to the general
ephemeral/unreserved ranges. This is a diagnostic/API listener only; it does
not allow the daemon to act as a database server.

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
  - runtime helper executables (including the MTU-patched `wg-quick`) ->
    `wifiman_runtime_exec_t`
  - `/var/lib/wifiman-desktop` and all other runtime/state data ->
    `wifiman_var_t`
- The packaged tree is read-only to `wifiman_t`; an attempted create under
  `/usr/lib/wi-fiman-desktop` was denied. Runtime copies are made with
  `cp -a --no-preserve=context`, so copied data stays `wifiman_var_t` and only
  the named helpers receive `wifiman_runtime_exec_t`. There are no relabel
  grants; `wg-quick` is rewritten through its existing inode.
- The pruned capability/process set (only `net_admin`, `net_raw` plus the
  process-management permissions listed above) still starts the daemon, binds
  the local API and sets up the WireGuard interface.
- Reviewed AVC policy is installed before the first dedicated restart and is
  verified by the dedicated-domain test. If a reviewed module references
  `wifiman_t` and the dedicated start fails, the installer removes that module
  before loading the legacy base (which does not define `wifiman_t`).
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
- Final VM check on 540a717: the no-relabel MTU rewrite kept `wg-quick` at
  `wifiman_runtime_exec_t` and brought the interface up at MTU 1280 without an
  AVC. A forced dedicated failure with a reviewed AVC module that references
  `wifiman_t` removed that module before the legacy base was installed; the
  resulting module list contained only the legacy base, with no unresolved-type
  failure.
- `./tests/run-all.sh` passes, including the dedicated-domain installer test,
  reviewed-AVC ordering, runtime copy context handling, offline compilation of
  both policy sources, fallback behavior, and the existing installer/removal
  tests.

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
6. Re-check the policy after #36 (1.3.0). The daemon side is reported unchanged,
   but the validation above used the 1.2.10 package and the new UI may exercise
   different compatibility libraries.

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
