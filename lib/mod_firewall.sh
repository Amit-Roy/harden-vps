# shellcheck shell=bash
# shellcheck disable=SC2034
FW_ROLLBACK_UNIT=vps-harden-fw-rollback

mod_firewall() {
  local iface tcp udp p rules="" had_change
  iface=$(vh_public_iface)
  if [ -z "$iface" ]; then
    skip_system || die "firewall: cannot detect the public interface; set PUBLIC_IFACE"
    warn "firewall: no default route here; rendering with iface 'eth0'"; iface=eth0
  fi
  [[ "$iface" =~ ^[A-Za-z0-9._-]+$ ]] || die "firewall: bad interface name '$iface'"
  PUBLIC_IFACE=$iface

  if [ "$SSH_PUBLIC" != yes ] && ! mod_enabled tailscale && ! command -v tailscale >/dev/null 2>&1 && [ "$FW_FORCE" != yes ]; then
    die "firewall: SSH_PUBLIC=no and no tailscale: you would lose SSH. Enable the tailscale module, set SSH_PUBLIC=yes, or FW_FORCE=yes if you have another way in"
  fi

  tcp="$FW_TCP_PORTS"; udp="$FW_UDP_PORTS"
  [ "$SSH_PUBLIC" = yes ] && tcp+=" $SSH_PORT"
  mod_enabled tailscale && udp+=" 41641"
  for p in $tcp $udp; do [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le 65535 ] || die "firewall: bad port '$p'"; done
  # shellcheck disable=SC2086
  tcp=$(printf '%s\n' $tcp | sort -un | paste -sd, | sed 's/,/, /g')
  # shellcheck disable=SC2086
  udp=$(printf '%s\n' $udp | sort -un | paste -sd, | sed 's/,/, /g')
  [ -z "$tcp" ] || rules+="    tcp dport { $tcp } accept"$'\n'
  [ -z "$udp" ] || rules+="    udp dport { $udp } accept"$'\n'
  INPUT_RULES=${rules%$'\n'}

  CHANGED=0
  install_tpl 0600 files/nft/host_guard.nft /etc/vps-harden/host_guard.nft PUBLIC_IFACE INPUT_RULES
  put 0644 /etc/systemd/system/vps-harden-firewall.service < "$REPO/files/systemd/vps-harden-firewall.service"
  had_change=$CHANGED

  if skip_system; then log "skip: load firewall (public iface $iface)"; return 0; fi
  nft -c -f /etc/vps-harden/host_guard.nft || die "firewall: generated ruleset is invalid"
  systemctl daemon-reload
  if [ "$had_change" = 0 ] && systemctl is-active -q vps-harden-firewall.service; then
    log "firewall unchanged and active"; return 0
  fi

  if [ "$AUTO_CONFIRM" = 1 ]; then
    systemctl enable vps-harden-firewall.service
    systemctl restart vps-harden-firewall.service
    log "firewall active and enabled (auto-confirmed, no rollback window)"
    return 0
  fi
  # Safe apply: schedule an automatic undo before loading, cancel it only after a fresh login works.
  systemctl stop "$FW_ROLLBACK_UNIT.timer" "$FW_ROLLBACK_UNIT.service" 2>/dev/null || true
  systemd-run --quiet --unit="$FW_ROLLBACK_UNIT" --on-active=300 --description="vps-harden firewall auto-rollback" \
    /bin/systemctl disable --now vps-harden-firewall.service
  systemctl restart vps-harden-firewall.service
  cat >&2 <<MSG
[vps-harden] Firewall LOADED on '$iface' with a 5 minute auto-rollback.
  Open a NEW ssh session now. If it works, run there:   vps-harden confirm-firewall
  If you do nothing, the firewall is removed in 5 minutes (disabled, not loaded at boot).
MSG
}
