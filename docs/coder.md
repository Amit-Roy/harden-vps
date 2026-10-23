# Coder hardening notes

Environment for the Coder server (compose or systemd):

```
CODER_DISABLE_PASSWORD_AUTH=true     # SSO / OIDC only, no password logins to brute force
CODER_DISABLE_PATH_APPS=true         # path-based apps share the dashboard origin: one malicious app could steal sessions
CODER_WILDCARD_ACCESS_URL=*.coder.example.com   # needed for subdomain apps once path apps are off
```

Publish ports on loopback only and let the reverse proxy be the front door:

```yaml
services:
  coder:
    ports:
      - "127.0.0.1:7080:7080"
```

Docker `-p 7080:7080` publishes on all interfaces and bypasses classic input filtering. The `vps-harden` firewall also drops
non-established forwarded traffic from the public interface, but loopback binding is the belt to that suspenders.

## Applying a change safely

Changing server env on a remote box can leave it down. Keep the previous file and let a script roll back:

```bash
cd /opt/coder
cp compose.yaml compose.yaml.vps-harden-prev
$EDITOR compose.yaml
vps-harden-safe-restart /opt/coder coder http://127.0.0.1:7080/healthz 180
```

It runs `docker compose up -d coder`, polls the health URL, and restores `compose.yaml.vps-harden-prev` if the service is not
healthy within the timeout. Keep unattended upgrades from restarting Docker by default: `UU_BLACKLIST="docker- containerd.io"`.
