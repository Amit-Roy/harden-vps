# shellcheck shell=bash
# shellcheck disable=SC2034
mod_tailscale() {
  local cn; cn=$(os_codename)
  [ -n "$cn" ] || die "tailscale: cannot detect distro codename"
  if ! skip_system && [ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]; then
    local distro; distro=$(. /etc/os-release; echo "$ID")
    curl -fsSL "https://pkgs.tailscale.com/stable/$distro/$cn.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL "https://pkgs.tailscale.com/stable/$distro/$cn.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
    APT_UPDATED=0
  fi
  apt_install tailscale
  run systemctl enable --now tailscaled
  if skip_system; then return 0; fi
  if tailscale status >/dev/null 2>&1; then
    log "tailscale already connected"
  elif [ -n "${TS_AUTHKEY:-}" ]; then
    local kf; kf=$(mktemp); chmod 600 "$kf"; printf '%s' "$TS_AUTHKEY" > "$kf"
    # shellcheck disable=SC2086
    tailscale up --auth-key="file:$kf" $TS_ARGS || { rm -f "$kf"; die "tailscale up failed"; }
    rm -f "$kf"
  else
    log "tailscale installed, not connected. Run: tailscale up ${TS_ARGS:---ssh}"
  fi
}
