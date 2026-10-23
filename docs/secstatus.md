# secstatus

Read-only status API for the other modules. `sec-status-api` is an SSH forced command: it accepts exactly one word, `status`, and prints JSON about the systemd timers and services of `secscan`, `osv` and the Falco alert forwarder. It changes nothing and no argument reaches a shell.

The module installs `/usr/local/sbin/sec-status-api` and `/etc/sec-status/units.json` (an existing `units.json` is never overwritten). It does **not** create SSH keys or edit `authorized_keys`. Generate a key on the reader, then add this line to `/root/.ssh/authorized_keys` yourself:

```
restrict,command="/usr/local/sbin/sec-status-api" ssh-ed25519 AAAA... status-reader
```

Query it with `ssh -i <key> root@host status`. Set `SEC_STATUS_CONFIG` to read a different config file.

## Output

```json
{"generatedAt": 1700000000000, "units": [
  {"id": "osv", "name": "OSV malware check", "link": "/security", "schedule": "Daily",
   "periodSec": 86400, "runnable": null, "continuous": false, "active": "active",
   "running": false, "ok": true, "detail": null, "lastRun": 1699990000000, "next": 1700080000000}
]}
```

- `id`, `name`, `link`, `schedule`: labels from `units.json`.
- `periodSec`: expected interval in seconds. `continuous`: long-running service.
- `runnable`: optional action name from the config, else `null`.
- `active`: systemd state of the timer (or service). `running`: service is currently activating.
- `ok`: `false` when a unit failed, is stale, or a file check fails. `detail`: reasons joined by `; `, else `null`.
- `lastRun`, `next`: milliseconds since epoch, or `null` when unknown.

## Config

`units.json` holds `units[]` with `id`, `name`, `link`, `schedule`, `periodSec`, `timer`, `service`, optional `continuous`, `alsoActive` (extra units that must be active) and `file` (`path`, `maxAgeSec`: the file must not be older than this). Edit it to add your own units.
