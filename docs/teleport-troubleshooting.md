# Teleport reconnect troubleshooting

This page is for the failure tracked in
[issue #27](https://github.com/iamstevedavis/wifiman-rpm/issues/27): Teleport
connects, then drops and reconnects roughly every 15 seconds. The daemon log
shows 10 missed UDP echo replies over IPv6 inside the tunnel, followed by
`TELEPORT_UDP_ECHO_FAILED` and `Stopping teleport`. The WireGuard handshake
sometimes never completes, and `wg show` reports
`transfer: 0 B received, 444 B sent`.

## Status: what is confirmed

The RPM does **not** control the direct/relay (ICE/STUN/TURN) choice or the
daemon's 10-strike echo teardown. Those are upstream daemon behaviour.

Offline inspection of the upstream 1.3.0 and 1.2.10 `.deb` packages confirms:

| Item | 1.2.10 | 1.3.0 |
| --- | --- | --- |
| `.env`, `.env.development`, `.env.staging` | SHA256 `40a3a08e…`, `111e6ca…`, `5345a12…` | byte-identical |
| `wg-quick` | SHA256 `5b2aa961…` | byte-identical |
| `wg_report.sh` | SHA256 `efef2719…` | byte-identical |
| ICE/STUN library (`pion/stun`) | `v0.3.5` | `v0.3.5` |
| Teleport helper library (`shared-utils.teleport-go`) | `v0.0.0-20230222120613-60838c7597a4` | same |
| WireGuard control library (`wgctrl`) | `v0.0.0-20211027125547-828be3fd529a` | same |
| Daemon Go toolchain | Go 1.22.2 | Go 1.26.1 |
| MQTT client | `paho.mqtt.golang v1.4.3` | `v1.5.1` |

The `.env` file has no pinger, retry, ICE, relay or handshake tuning knobs.
The only Teleport-related values are operation timeouts such as
`SERVICE_TELEPORT_ON_TIMEOUT=60000`; none of them is an echo-check or retry
setting.

The daemon's `runUdpEchoPinger` still contains the same 10-strike threshold and
the same 1.5-second sleep in both releases. Reverse engineering shows the same
`cmp $0xa` after the counter increment and the same `0x59682f00` ns sleep in
each binary, which matches the observed ~15-second loop. The 1.3.0 function is
not byte-identical: it reads the echo reply with a deadline before the
sleep/`wg show` phase, while 1.2.10 sleeps first. Whether that ordering change
helps the direct-path failure is **unknown**.

1.3.0 also adds orphaned-tunnel cleanup, `waitForInterfaceGone`, hostname
validation and console-metadata refresh. Those are useful robustness changes,
but they do not add a documented setting for the echo check.

## What the packaging does and does not do

- It does **not** ship or modify firewalld, nftables or iptables rules. The RPM
  file list contains no firewall configuration. If a firewall is the cause, it
  is the system's own firewalld/nftables policy, not an RPM rule.
- The daemon wrapper mirrors a fixed set of upstream files into
  `/var/lib/wifiman-desktop/app-root`, preserves `service.json`, and runs the
  mirrored `wifiman-desktopd`. It does not choose direct versus relay.
- The runtime mirror patches only the copied `wg-quick` to cap the tunnel MTU
  at 1280. The packaged `wg-quick` is untouched. A handshake initiation is far
  smaller than 1280 bytes, so this cap cannot explain `0 B received` in the
  handshake. It can still matter for data inside a tunnel that came up.
- The systemd unit uses `Restart=always`. That is separate from the daemon's
  internal Teleport reconnect loop. Check `NRestarts` before blaming systemd.
- The upstream `.deb` depends on `resolvconf`, and `wg-quick` calls it when the
  tunnel config sets DNS. This RPM does not currently require it. If a manual
  `wg-quick` run fails with `resolvconf: command not found`, install
  `systemd-resolved` or `openresolv` and include that in the report. This is a
  packaging gap versus upstream, but it is not established as the cause of the
  intermittent reconnect loop.

### SELinux caveat for the dedicated policy

The dedicated `wifiman_t` policy is a local workaround, not an upstream Fedora
policy. If you installed it, check for AVCs before assuming the network is at
fault. The daemon binary carries this `wireguardAllowedIPs` value:

```text
0.0.0.0/0, ::0/0
```

When that value lands in the generated WireGuard config, `wg-quick` treats it
as a default route and runs
`sysctl -q net.ipv4.conf.all.src_valid_mark=1` from `add_default()`. The
dedicated policy allows `sysctl` execution but has no
`sysctl_net_t:file write` rule, and it allows only read access to `net_conf_t`.
That is a **candidate** for a wg-quick setup failure on hosts using the
dedicated policy. It is not proven to be the cause of issue #27, and the policy
must not be broadened speculatively. Capture the AVC first; if it appears, it
needs a reviewed policy change rather than a blind allow rule.

## Capture procedure

Use two terminals. Run these while Teleport is in its reconnect loop. Replace
`<peer-tunnel-ipv6>` with a reachable IPv6 address inside the tunnel if you
have one.

### 1. Basic package and service state

```bash
rpm -q wifiman-desktop
getenforce
systemctl show wifiman-desktop -p NRestarts -p ExecMainStartTimestamp -p Environment
sudo systemctl status wifiman-desktop --no-pager -l
```

### 2. Follow the daemon log

```bash
sudo journalctl -u wifiman-desktop -f --no-pager | tee /tmp/wifiman-teleport-journal.log
```

Look for the 10 timeouts, `TELEPORT_UDP_ECHO_FAILED`, `Stopping teleport`, and
any `wg-quick` or SELinux error immediately before them.

### 3. Snapshot WireGuard, routes and IP rules

```bash
{
  date -Is
  sudo wg show all
  sudo wg show all latest-handshakes
  sudo wg show all transfer
  sudo wg show all dump
  ip -brief address
  ip route show table all
  ip -6 route show table all
  ip rule show
  ip -6 rule show
  ip link show
  sysctl net.ipv4.conf.all.src_valid_mark
  sysctl net.ipv6.conf.all.disable_ipv6
} | tee /tmp/wifiman-teleport-state.log
```

Repeat the `wg show all transfer` line a few times during the loop. A value of
`0 B received` with `444 B sent` means three handshake initiations got no
reply. Increasing received bytes means the handshake completed.

If a tunnel interface exists, also capture its addresses and test IPv6 inside
it:

```bash
tun=$(sudo wg show interfaces | awk '{print $1; exit}')
ip addr show dev "$tun"
ip -6 addr show dev "$tun"
ip -6 route show dev "$tun"
ping -6 -c 3 -W 1 -I "$tun" <peer-tunnel-ipv6>
```

### 4. Collect the packaged diagnostics

```bash
./scripts/collect-wifiman-debug-logs.sh
```

The collector now includes the WireGuard state, routes, IP rules, firewall
zones/rules, `LogDenied`, and filtered AVCs. It writes
`/tmp/wifiman-debug.log` by default.

### 5. Inspect firewalld

```bash
sudo firewall-cmd --state
sudo firewall-cmd --get-default-zone
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all-zones
sudo firewall-cmd --get-log-denied
```

Then enable drop logging for the duration of one failing attempt:

```bash
sudo firewall-cmd --get-log-denied          # note the current value
sudo firewall-cmd --set-log-denied=all
# reproduce the reconnect loop
sudo journalctl -k -f
# in another terminal, or after reproducing:
sudo journalctl -k --since '10 min ago' |
  grep -E 'DROP|REJECT|IN=|OUT='
sudo firewall-cmd --set-log-denied=off      # or restore the value printed above
```

`--set-log-denied` is a runtime setting. If you also use `--permanent`, turn it
off permanently and reload when you are done:

```bash
sudo firewall-cmd --permanent --set-log-denied=off
sudo firewall-cmd --reload
```

For a raw ruleset snapshot (firewalld may be using nftables):

```bash
sudo nft list ruleset | tee /tmp/wifiman-nft-ruleset.log
sudo iptables-save > /tmp/wifiman-iptables.log
sudo ip6tables-save > /tmp/wifiman-ip6tables.log
```

Interpretation: a logged `DROP`/`REJECT` for the WireGuard endpoint, the tunnel
interface, or the tunnel IPv6 prefix is evidence that the firewall is involved.
No matching drop means the firewall is not the first thing to chase.

### 6. Check SELinux and wg-quick

```bash
getenforce
ps -eo pid,label,comm | grep -Ei 'wifiman|wireguard'
sudo ausearch -m AVC -ts recent |
  grep -Ei 'wifiman|wg-quick|wireguard|sysctl_net_t|net_conf_t|nft|iptables' -A5 -B2
```

Also inspect the runtime copy and the MTU patch:

```bash
sudo ls -l /var/lib/wifiman-desktop/app-root
sudo grep -n 'wifiman: WireGuard MTU cap' /var/lib/wifiman-desktop/app-root/wg-quick
```

If `wg-quick` failed, capture its stderr. The daemon log is the usual place; if
you can reproduce manually, use the runtime copy so SELinux labels and the MTU
cap match:

```bash
sudo /var/lib/wifiman-desktop/app-root/wg-quick up <interface>
sudo /var/lib/wifiman-desktop/app-root/wg-quick down <interface>
```

Do not run the packaged `wg-quick` directly for this comparison, and do not
change `scripts/wifiman-desktop.te` just to make an AVC disappear.

## Reading the result

- **Handshake never completes, `0 B received`:** direct path is not getting a
  reply. Compare the same operation on a different network and via relay. This
  is the case issue #27 describes.
- **Handshake completes, transfer grows, pinger still fails:** look at IPv6
  inside the tunnel, the tunnel MTU, and the local firewall. Try a small
  IPv6 ping to distinguish a broken route from an MTU problem.
- **No tunnel interface:** `wg-quick` failed before or during setup. Check the
  journal for its exact error and for the SELinux caveat above.
- **`NRestarts` increases:** systemd restarted the service. That is different
  from the daemon's internal Teleport stop/reconnect cycle.
- **Relay works but direct does not:** the failure is in hole punching or the
  direct path, not in the RPM launcher or the state mirror.

## Reporting upstream

Include the WiFiman version (`rpm -q wifiman-desktop`), Fedora/kernel version,
network type, whether relay works, the `wg show` snapshot before and after a
failure, the daemon log excerpt, the firewalld `LogDenied` result, and any AVC.
Say explicitly whether the direct path worked on a different network.

Do not paste tokens, `service.json`, private keys, or unredacted audit logs.

## Reset after capture

Turn logging back off and keep the logs:

```bash
sudo firewall-cmd --set-log-denied=off
```

If you need to reset local WiFiman state, use the packaged helper after saving
the logs:

```bash
./scripts/remove-wifiman-desktop.sh
```

That removes `/var/lib/wifiman-desktop` and per-user state. It keeps local
SELinux modules unless `REMOVE_SELINUX_MODULES=1` is set.
