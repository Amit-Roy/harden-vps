# Recovery: undo the firewall or SSH hardening

You locked yourself out? Use your provider's web console (VNC / serial / "rescue" console). It does not need the network path the firewall filters.

## Firewall

```bash
systemctl stop vps-harden-firewall      # deletes the nftables table inet host_guard
systemctl disable vps-harden-firewall   # do not load it at boot
nft list tables                          # inet host_guard must be gone
```

Fix `/etc/vps-harden/config.env` (open ports, `SSH_PUBLIC`, tailscale), then re-run the installer
with `--modules firewall`. The rest of the ruleset (Docker, Tailscale) is untouched: the firewall owns only its own table.

If you never ran `vps-harden confirm-firewall`, a transient timer already did the above 5 minutes after loading.

## SSH

```bash
rm /etc/ssh/sshd_config.d/00-vps-harden.conf
sshd -t && systemctl reload ssh
```

Then add your public key to `~/.ssh/authorized_keys` and re-run the installer.

## fail2ban banned you

```bash
fail2ban-client set sshd unbanip <your-ip>
```
