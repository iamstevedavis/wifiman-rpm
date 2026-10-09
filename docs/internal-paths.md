# Internal path decision (issue #9)

## Decision

Keep `/usr/lib/wi-fiman-desktop` as the RPM's private, read-only app root and
`wi-fiman-desktop-bin` as its private UI executable. Public names remain
`wifiman-desktop` (package, command, icon and service) and `WiFiman Desktop`
(menu entry). The private spelling is a compatibility detail, not an alternate
user-facing command.

Normalizing this directory offers no functional improvement. It would change
the RPM file inventory, wrapper defaults, helper lookup, systemd `ExecStart`,
diagnostics and installed-layout tests at once. It would also require checking
upstream binaries and scripts for absolute-path assumptions on a real Fedora
host. The mock regression suite cannot establish that compatibility. Preserving
the existing path is preferable to a cosmetic migration with that risk.

## Reference audit

The repository references fall into these groups:

| Area | References and contract |
| --- | --- |
| RPM installation | `wifiman-desktop.spec` installs the UI as `wi-fiman-desktop-bin`, copies the upstream library payload, installs `compat`, both wrapper/helper files and the relative log link under `/usr/lib/wi-fiman-desktop`. Its `%files` list owns that same tree. |
| Upstream spelling compatibility | The spec accepts both `wi-fiman-desktop` and `wifiman-desktop` spellings for the extracted executable, library directory and icons, but always installs one stable private RPM layout. `stage-wifiman-fedora-newer.sh` searches both library-directory spellings. |
| Installed wrappers | `wifiman-desktop-launcher.sh` and `wifiman-desktopd-wrapper.sh` default `APP_ROOT` to the retained path. The launcher finds the installed runtime helper there and executes the private UI name from writable state. The daemon finds the helper beside its installed wrapper. |
| systemd | The spec rewrites the installed unit's `ExecStart` to `/usr/lib/wi-fiman-desktop/wifiman-desktopd-wrapper`. The copied upstream unit inside the private payload is not the active system unit. |
| Desktop integration | `wifiman-desktop.desktop` uses `Exec=wifiman-desktop %U` and `Icon=wifiman-desktop`; neither references the private root. No desktop change is needed. |
| Mutable state | `wifiman-runtime.sh` selectively mirrors required items into `app-root` under per-user XDG state or `/var/lib/wifiman-desktop`. The private UI name is selected by the launcher. Packaged log links, unit files and helpers are excluded; stale entries are cleaned without replacing persistent runtime `service.json`. |
| SELinux | `wifiman-desktop.te` uses types, not pathname rules; there is no `.fc` file or custom file-context mapping in this repository. The current shared-label policy is documented in `selinux-validation.md` and tracked separately in #15. Retaining the root requires no policy or label migration. |
| Diagnostics | `collect-wifiman-debug-logs.sh` inspects the retained installed root and the public launcher. |
| Staged execution | `wi-fiman-desktop-wrapper.sh`, `build-rpm-from-stage.sh`, `verify-fedora-newer-stage.sh` and `test-fedora-newer-stage-in-container.sh` refer to upstream/stage `wi-fiman` names, not the installed RPM layout. The staging wrapper and verification scripts still assume the legacy upstream executable spelling; accepting both spellings in the spec does not imply all staging tools support both. |
| Tests | Launcher, shared-runtime, daemon/runtime-wrapper and log-link tests model the existing private layout. `test-internal-path-contract.sh` additionally exercises the spec's app/wrapper/unit installation commands with both upstream spellings and checks the wrapper defaults and packaged paths agree. |
| Documentation | `README.md`, `AGENTS.md` and `selinux-validation.md` describe the installed root. `FEDORA_NEWER_NOTES.md` includes historical upstream and `/opt` staging examples, not the current RPM install contract. Release workflow notes now state that the private path is intentionally retained. |

To repeat the spelling audit (including hidden workflow files):

```bash
git grep -n -E 'wi-fiman|/usr/lib/wifiman'
```

## Upgrades

There is no path migration and no clean reinstall requirement for this decision.
Use the normal DNF RPM upgrade process. The package name, file paths, active unit
path and state roots are unchanged. The existing `%config(noreplace)` service
configuration and runtime persistence behavior remain in place; do not remove
state to normalize a private directory name.

Any future rename should be a separately tested migration: inspect upstream
absolute-path use, test an actual old-to-new RPM transaction with an enabled
daemon and existing user/system state, verify enforcing-SELinux labels and
execution, and decide whether an RPM-owned compatibility link is required.
Do not simply replace every `wi-fiman` occurrence: some identify upstream input
paths or historical examples rather than package-owned destinations.
