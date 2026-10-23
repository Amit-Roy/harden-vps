# harden-vps: one-command Linux VPS security hardening (Debian/Ubuntu): firewall, Falco, ClamAV, Trivy, fail2ban, Tailscale, supply-chain malware checks

Idempotent installer that turns a fresh Debian VPS into a hardened server: default-deny nftables firewall that also closes the
Docker published-port bypass, key-only SSH, fail2ban, unattended security upgrades, Falco runtime detection, weekly
ClamAV/Trivy/nmap scans, daily known-malicious-package checks, and alerts to your inbox or phone. Built to be run by you or by a coding agent.

Targets Debian 12 and 13 (tested). Ubuntu is best-effort and untested: the apt repos and unit names are the same, expect to adjust.

## Quick start

```bash
# On the VPS, as root. Add your SSH public key first: the installer refuses to disable passwords without one.
npx harden-vps install --dry-run                       # preview, changes nothing
sudo npx harden-vps install --modules ssh,fail2ban,sysctl,unattended,tailscale,firewall
# then, from a NEW ssh session:
vps-harden confirm-firewall                            # otherwise the firewall rolls itself back in 5 minutes
```

No npm? `git clone` the repo and run `sudo ./install.sh --modules ...`. Config lives in `/etc/vps-harden/config.env`
(template: [`config.example.env`](config.example.env)); flags override it. Coding agents: see [`SKILL.md`](SKILL.md).

Dev box or container (non-root): `npx harden-vps workstation` sets package-manager cooldowns and installs install-time malware blocking.

## Features

- **Firewall (nftables, IPv4+IPv6)**: own table `inet host_guard`, filters only the auto-detected public interface, closes the Docker `-p` bypass, safe apply with automatic 5 minute rollback.
- **SSH**: key-only, no root password, no forwarding, 3 tries; refuses to apply when no authorized key exists.
- **fail2ban**: sshd jail on the systemd journal, 1h ban escalating to 1 week.
- **unattended-upgrades**: Debian + security origins, never reboots, never touches Docker unless you say so.
- **sysctl**: loose rp_filter (Tailscale-safe), kptr_restrict, ptrace_scope, no redirects.
- **Tailscale** (optional): official apt repo, SSH over the tailnet while the public port stays closed.
- **Falco**: eBPF runtime detection, JSON output, webserver off, noise exceptions.
- **Alerts**: Falco digest every 5 minutes through `agentmail`, `ntfy`, `webhook` or `smtp`.
- **secscan**: weekly ClamAV (temporary multithreaded clamd + AppArmor override), Falco summary, Trivy, nmap; JSON results and a forced-command API.
- **Trivy**: pinned, sha256 + cosign verified, held, compromised 0.69.4-0.69.6 refused.
- **osv-malware-check**: daily OSV `MAL-` advisories over your lockfiles, alerts on new hits only.
- **Canary** (optional): fake AWS keys that email you when an intruder uses them.
- **Workstation**: npm `min-release-age`, uv `exclude-newer`, SafeDep PMG, all pinned.

## Modules

| Module | What | Why |
|---|---|---|
| `ssh` | `/etc/ssh/sshd_config.d/00-vps-harden.conf` | Password guessing is constant background noise; keys end it. |
| `fail2ban` | sshd jail, nftables ban action | Cuts log spam and slows what remains. |
| `unattended` | security origins, blacklist, no reboot | Patches land without surprise container restarts. |
| `sysctl` | `90-vps-harden.conf` | Kernel pointer leaks, ptrace, redirects. |
| `firewall` | `vps-harden-firewall.service` + `host_guard.nft` | Default deny; Debian's `nftables.service` flushes the whole ruleset (Docker, Tailscale), so this uses its own table and unit. |
| `tailscale` | apt repo, optional `tailscale up` | Private path in when public SSH is closed. |
| `falco` | official repo, modern eBPF | Detects shells in containers, sensitive reads, drift. |
| `alerts` | `vps-harden-notify`, `falco-alert*` | A detector nobody hears is useless. |
| `secscan` | `secscan`, `secscan-api`, timer | Weekly malware, CVE and exposure sweep. |
| `trivy` | verified pinned `.deb` | Scanner from a supply chain you can verify. |
| `osv` | pinned `osv-scanner`, daily timer | Catches malicious dependencies that already landed. |
| `secstatus` | `sec-status-api`, `/etc/sec-status/units.json` | Read-only SSH status API for the units above, see [`docs/secstatus.md`](docs/secstatus.md). |
| `canary` | `/root/.aws/credentials` profile `backup-admin` | Tripwire for credential theft. |

## Threat model

In scope: internet-wide scanning and brute force, accidentally published container ports, kernel info leaks, unpatched packages,
malicious npm/PyPI dependencies, credential theft from a compromised workspace.
Out of scope: a determined attacker with kernel exploits or root already, provider-level compromise, targeted phishing. This is a
solid baseline, not a certification.

## Safety design

- Firewall applies with a `systemd-run --on-active=300` rollback; `vps-harden confirm-firewall` from a new SSH session cancels it. `--firewall-auto-confirm` skips the window for agents that verified a fresh login themselves. Recovery from the provider console: [`docs/RECOVERY.md`](docs/RECOVERY.md) (`systemctl stop vps-harden-firewall`).
- `SSH_PUBLIC=no` without Tailscale is refused (you would lose SSH) unless `FW_FORCE=yes`.
- Trusted by design: loopback, `tailscale0`, Docker bridges (only the public interface is filtered).
- Secrets live only in `/etc/vps-harden/config.env` (root, mode 600) and are passed to curl through pipes, not argv.
- nmap run from the host against its own public IP takes the loopback path and bypasses the firewall. Verify exposure from outside: [`docs/external-port-check.md`](docs/external-port-check.md).

## Offline test and preview

```bash
./install.sh --root /tmp/render --dry-run --modules ssh,sysctl     # render files, run nothing
bash test/run.sh                                                    # shellcheck + render + nft syntax
```

## Guides

[Caddy security headers](docs/caddy.md) · [Coder hardening](docs/coder.md) · [External port check](docs/external-port-check.md) · [Recovery](docs/RECOVERY.md)

## FAQ

**How do I harden a new VPS?**
Add your SSH key, then run `sudo npx harden-vps install` with the modules you want. Start with `ssh,fail2ban,unattended,sysctl,firewall`, add monitoring (`falco,alerts,secscan,trivy,osv`) once an alert transport is configured.

**How to block Docker published ports with nftables?**
Docker publishes ports via DNAT and the FORWARD chain, so input rules never see them. The `host_guard` table hooks forward at priority -10 and drops anything that is not established/related from the public interface. Containers stay reachable from loopback, Tailscale and bridges.

**How do I close public SSH and still log in?**
Set `SSH_PUBLIC=no`, enable the `tailscale` module, and connect over the tailnet. The firewall filters only the public interface.

**How do I avoid locking myself out of my VPS with a firewall?**
The installer schedules an automatic rollback before loading. Confirm from a second session or wait five minutes. Console recovery steps are in `docs/RECOVERY.md`.

**Why not use Debian's nftables.service?**
Its config starts with `flush ruleset`, which deletes the rules Docker and Tailscale installed. `vps-harden` manages only `inet host_guard`.

**How do I stop unattended upgrades from restarting my containers?**
`UU_BLACKLIST="docker- containerd.io"` (the default) keeps those packages out of automatic upgrades; upgrade them by hand in a window you choose.

**How do I get alerts from Falco on my phone or email?**
Set `ALERT_TRANSPORT` to `ntfy`, `agentmail`, `webhook` or `smtp` in the config. `vps-harden test-alert` sends a test message.

**How do I detect malicious npm or PyPI packages already on my server?**
The `osv` module runs `osv-scanner` daily over `OSV_PATHS` and alerts on new OSV `MAL-` advisories. For prevention on a dev machine use `harden-vps workstation`.

**How do I verify my firewall from the outside?**
`vps-harden-portcheck <ip> <ports...>` (check-host.net). Do not trust a scan from the server to its own IP.

**How do I know a Trivy download is genuine?**
Pinned version, cosign signature of the release checksums verified against the project's GitHub Actions identity, sha256 of the `.deb` checked, package held. Versions 0.69.4-0.69.6 are refused (GHSA-69fq-xp46-6x23).

## vps-harden vs manual hardening

| | vps-harden | By hand / copy-pasted guide |
|---|---|---|
| Repeatable on every new server | Yes, idempotent | Drift between servers |
| Firewall keeps Docker/Tailscale rules | Own table and unit | `nftables.service` flush wipes them |
| Docker `-p` bypass closed | Yes | Usually forgotten |
| Lockout protection | Auto-rollback + confirm | You and a VNC console |
| Downloads verified | Pinned sha256 + cosign | `curl \| sh` |
| Alerts | One notify helper, 4 transports | Per-tool email setup |
| Agent-friendly | `SKILL.md`, `--dry-run`, `--root` | No |
| Coverage | You choose modules | Whatever you remember |

## Contributing

Run `bash test/run.sh` before sending a change. No personal data in examples: use `example.com`, `203.0.113.0/24`, `2001:db8::/32`.

## License

MIT
