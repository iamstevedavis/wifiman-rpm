# SELinux scope migration / issue #15

## Status and limits

The existing base module is **not confined to WiFiman**: its `init_t` rules
affect every process in that shared domain, and `lib_t`, `var_lib_t`, and
`init_var_lib_t` are shared object types. Filtering audit records by `comm`
does not narrow the resulting allow rules. The installer now saves generated
AVC rules for review rather than installing them automatically. Supplying
`REVIEWED_AVC_TE` explicitly authorizes compiling and installing that source.
Existing local modules are not removed by this change; inspect them separately.

No enforcing Fedora reproduction or domain migration has been validated on the
development host (Ubuntu without SELinux tooling/enforcement). Shell mocks and
offline policy compilation cannot establish that discovery or VPN works.
Issue #15 remains unresolved until the migration and enforcing tests below pass.

## Layout audit and proposed migration

- The systemd entry point is
  `/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper`. It creates a selective
  runtime mirror under `/var/lib/wifiman-desktop/app-root`, changes directory
  there, then executes the copied daemon.
- `service.json`, `service.json.tmp`, and logs belong in system state. The
  packaged log path is a symlink into that state. The UI uses per-user state;
  it must not enter the system daemon's domain.
- No explicit wrapper write targets the packaged tree. This is not evidence
  that the opaque upstream executable never writes an absolute `/usr/lib` path.
  Audit actual filesystem activity before removing the legacy write rules.
- A dedicated `wifiman_t` daemon domain should transition from systemd at the
  wrapper entry point, with a dedicated entry-point label. Packaged data and
  system state need separate labels. Move network grants off `init_t`, and
  replace generic helper-file grants with rules for WiFiman state only.
- Account for copied `wifiman-desktopd`, `wireguard-go`, `wg`, `wg-quick`, and
  `wg_report.sh`, plus compatibility libraries. The wrapper's `cp -a` preserves
  security contexts where supported, but it also deletes and recreates runtime
  items on every start. Persistent file-context mappings alone do not label
  newly created files. Specify and test creation transitions or relabeling at
  the correct point on **every** restart, including first creation of state.
  Distinguish the wrapper's entry-point type from helper executable types so
  copied helpers do not accidentally transition domains.
- Do not permit execution of every writable state file as a shortcut. Establish
  the minimum helper transitions, library access, capabilities, device access,
  and network permissions from clean-state AVC evidence. Review any domain
  transition into Fedora's `ifconfig_t`/`iptables_t` helper domains.

## Enforcing Fedora validation (separate from packaging tests)

Use a disposable Fedora VM with a snapshot; do not erase production state.
Record Fedora, package and policy versions, `getenforce`, and the installed
local modules (`sudo semodule -lfull`). Disable/remove old local WiFiman grants
in the test VM before reproducing; otherwise they can mask missing rules.

1. Install the RPM into clean package and runtime state. Run `./tests/run-all.sh`
   separately and record packaging/wrapper results. Check service configuration
   with `systemctl cat wifiman-desktop.service` and confirm the log symlink.
2. Record the audit start time, launch the UI, start/restart the daemon, exercise
   discovery and a real Teleport/VPN session, disconnect/reconnect, and reboot.
   Capture `sudo ausearch -m AVC,USER_AVC -ts boot --raw`, service journal, and
   `ps -eZ`. Inspect process IDs/executable paths rather than assuming `comm`
   uniquely identifies this daemon or includes every helper.
3. Separate missing/broken runtime files, service config, ownership, and wrapper
   failures from genuine SELinux denials. Inspect labels with `ls -lZ` and
   `matchpathcon -V` on the packaged entry point, copied executables and state.
4. Audit writes during the same actions with an appropriate tracing/audit tool
   in the disposable VM, including absolute paths. Identify the writer and
   destination of every attempted packaged-tree write before dropping grants.
5. Review proposed policy source against that evidence. Reject generic file
   write permissions and shared-domain networking grants. Document the reason
   for each permission and helper transition; do not install raw audit2allow
   output just because its `comm` matches WiFiman.
6. Install the dedicated-domain policy, relabel only its owned paths, and repeat
   all actions with enforcement on. Verify the daemon runs as `wifiman_t`, the
   UI retains its expected domain, and labels survive restarts/reboot. Verify
   generated `service.json.tmp` is labeled as state and copied executables have
   their intended executable types.
7. Use policy queries (for example `sesearch -A -s init_t -t lib_t -c file`)
   and a before/after comparison to confirm this module adds no generic writes
   or shared-domain network grants. Test that unrelated daemon/file types do
   not inherit the new permissions. Check audit logs for new denials and record
   functional results independently of the packaging suite.

Attach the source/label policy, AVC evidence (redact credentials/network details),
policy queries, and action-by-action results to the PR before claiming closure.
