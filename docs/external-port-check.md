# Verify open ports from the outside

Scanning your own public IP from the host (including secscan's nmap step) takes the loopback path and bypasses the
firewall. Always confirm from another network.

```bash
vps-harden-portcheck 203.0.113.10 22 443 8080
```

It uses the check-host.net API:

```bash
curl -s -H 'Accept: application/json' 'https://check-host.net/check-tcp?host=203.0.113.10:443&max_nodes=3'
# -> {"ok":1,"request_id":"<id>", ...}
curl -s -H 'Accept: application/json' 'https://check-host.net/check-result/<id>'
# a node entry with "time" = connected; {"error":"Connection timed out"} = filtered
```

- IPv4 only: check-host.net does not support IPv6. Test IPv6 from a machine that has it (`nc -6 -zv host port`).
- Results fill in over several seconds; poll until no node is `null`.
- Expected after install: 443 open, 22 closed unless `SSH_PUBLIC=yes`, everything else closed (including published Docker ports).
