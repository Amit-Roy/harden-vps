---
name: vps-harden
description: Harden a fresh Debian 12/13 VPS with the vps-harden installer (nftables firewall that also closes Docker published ports, key-only SSH, fail2ban, unattended upgrades, Falco, ClamAV/Trivy/nmap scans, OSV malware checks, alerts, Tailscale, canary). Use when asked to secure, harden or lock down a VPS or server, set up a firewall, or add security monitoring and alerts.
---

# vps-harden

Run the idempotent installer on the target VPS (as root), verify access, confirm the firewall, then prove the result from outside.
Never run it on a machine the user did not name. Never print values from `/etc/vps-harden/config.env`.

## Steps

1. **Preflight.** Confirm with the user: target host, that they have a provider console (see `docs/RECOVERY.md`), whether SSH stays public (`SSH_PUBLIC`) or Tailscale-only, and which alert transport they want. Check that root (or `SSH_TARGET_USER`) has a key in `authorized_keys`; the ssh module refuses otherwise.
2. **Copy the repo.** `rsync -a --exclude .git ./ root@HOST:/root/vps-harden/` (or `git clone`, or `npx harden-vps`).
3. **Fill the config.** On the VPS: `cp config.example.env /etc/vps-harden/config.env; chmod 600 ...`. Set `MODULES`, `SSH_PUBLIC`, `FW_TCP_PORTS`/`FW_UDP_PORTS`, `ALERT_*`. Put secrets (API keys, `TS_AUTHKEY`) only in this file.
4. **Preview.** `./install.sh --dry-run` (add `--root /tmp/render` to inspect generated files).
5. **Run in two phases.** First `./install.sh --modules ssh,fail2ban,unattended,sysctl,tailscale` (add trivy,falco,alerts,secscan,osv as wanted). If Tailscale is used and `TS_AUTHKEY` is empty, run the printed `tailscale up` and confirm the node is reachable before step 6.
6. **Verify a fresh SSH login** in a NEW connection (key auth, and the tailnet address if `SSH_PUBLIC=no`). Do not close the original session until it works.
7. **Firewall.** `./install.sh --modules firewall`. It loads with a 5 minute auto-rollback. From the fresh SSH session run `vps-harden confirm-firewall`. If you already verified a fresh login yourself, `--firewall-auto-confirm` skips the window.
8. **External port check.** `vps-harden-portcheck <public-ipv4> 22 443 <other ports>` from outside the server. Expect only the ports in `FW_TCP_PORTS` open, and 22 closed unless `SSH_PUBLIC=yes`. Do not trust nmap run on the host itself.
9. **Test alert.** `vps-harden test-alert`; ask the user to confirm receipt. `systemctl start --no-block secscan.service` runs the first scan.
10. **Report** what was applied, what is closed, the rollback/recovery path, and any warnings. Mention the optional `secscan-api` forced-command line printed by the secscan module (never add it to `authorized_keys` unprompted).

## Rules

- If any step fails, stop and report; do not retry blindly. Firewall mistakes recover with `systemctl stop vps-harden-firewall` from the provider console.
- Re-running is safe; modules only rewrite files whose content changed.
- Dev box or container (non-root): `./workstation.sh` instead.
