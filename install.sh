#!/usr/bin/env bash
# vps-harden installer: idempotent hardening for a fresh Debian 12/13 VPS. Run as root.
# shellcheck disable=SC2034
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export REPO
ALL_MODULES="ssh fail2ban unattended sysctl tailscale trivy falco alerts secscan osv canary firewall"
DRY_RUN=0 ROOT="" CONFIG="" FLAG_MODULES="" AUTO_CONFIRM=0 CHANGED=0

usage() {
  cat <<USAGE
Usage: install.sh [install] [--modules a,b] [--dry-run] [--root DIR] [--config FILE]
                  [--firewall-auto-confirm] [--list] [-h]
  --modules LIST            comma list overriding MODULES from config
  --dry-run                 print actions, change nothing
  --root DIR                render all files under DIR; run no system command
  --config FILE             config file (default /etc/vps-harden/config.env)
  --firewall-auto-confirm   keep the firewall without the 5 minute rollback window
Modules: $ALL_MODULES
USAGE
}

[ "${1:-}" = install ] && shift
while [ $# -gt 0 ]; do
  case $1 in
    --modules) FLAG_MODULES=${2:?}; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --root) ROOT=${2:?}; shift 2 ;;
    --config) CONFIG=${2:?}; shift 2 ;;
    --firewall-auto-confirm) AUTO_CONFIRM=1; shift ;;
    --list) echo "$ALL_MODULES" | tr ' ' '\n'; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
ROOT=${ROOT%/}

# shellcheck source=lib/common.sh
. "$REPO/lib/common.sh"
# shellcheck source=lib/pins.sh
. "$REPO/lib/pins.sh"
# shellcheck source=bin/vps-harden-common.sh
. "$REPO/bin/vps-harden-common.sh"
for f in "$REPO"/lib/mod_*.sh; do
  # shellcheck disable=SC1090
  . "$f"
done

[ -n "$ROOT" ] || skip_system || [ "$(id -u)" = 0 ] || die "run as root"
if [ -z "$ROOT" ] && [ "$DRY_RUN" = 0 ]; then
  grep -qiE '^ID=(debian|ubuntu)' /etc/os-release 2>/dev/null || die "Debian (12/13) required"
fi

CONF_PATH=${CONFIG:-$ROOT/etc/vps-harden/config.env}
if [ -r "$CONF_PATH" ]; then
  # shellcheck disable=SC1090
  . "$CONF_PATH"
  [ -z "$ROOT" ] && [ "$DRY_RUN" = 0 ] && chmod 600 "$CONF_PATH"
else
  log "no config at $CONF_PATH, using defaults (copy config.example.env there to customise)"
fi

: "${MODULES:=ssh fail2ban unattended sysctl trivy falco alerts secscan osv firewall}"
: "${SSH_TARGET_USER:=root}" "${SSH_PORT:=22}" "${SSH_PUBLIC:=no}"
: "${FW_TCP_PORTS=443}" "${FW_UDP_PORTS=443}" "${FW_FORCE:=no}"
: "${UU_BLACKLIST=docker- containerd.io}" "${FALCO_EXCLUDE_CONTAINER_PREFIXES=}"
: "${ALERT_TRANSPORT:=none}"
: "${SCAN_PATHS=/root /home /etc /opt /usr/local /srv /tmp /var/tmp}" "${TRIVY_FS_PATHS=}" "${CLAMAV_EXTRA_EXCLUDES=}"
: "${SECSCAN_CALENDAR:=Sun *-*-* 02:00:00 UTC}" "${OSV_CALENDAR:=*-*-* 22:30:00 UTC}"
: "${TRIVY_VERSION:=0.76.1}" "${COSIGN_VERSION:=3.1.4}" "${OSV_SCANNER_VERSION:=2.7.0}"
: "${OSV_PATHS=/root /home /opt /srv}"
: "${CANARY_URL:=https://canarytokens.org/d3aece8093b71007b5ccfedad91ebb11/generate}"
: "${TS_ARGS=}" "${TS_AUTHKEY=}"
[ -z "$FLAG_MODULES" ] || MODULES=${FLAG_MODULES//,/ }
export MODULES

for m in $MODULES; do
  [[ " $ALL_MODULES " == *" $m "* ]] || die "unknown module: $m"
done

core_install

# Canonical order, not the order given.
for m in $ALL_MODULES; do
  if mod_enabled "$m"; then
    log "== module: $m"
    "mod_$m"
  fi
done

log "done. Config: /etc/vps-harden/config.env. Check: vps-harden firewall-status"
