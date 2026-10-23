# shellcheck shell=bash
# shellcheck disable=SC2034
mod_unattended() {
  apt_install unattended-upgrades apt-listchanges
  local lines="" p
  for p in $UU_BLACKLIST; do
    [[ "$p" =~ ^[A-Za-z0-9._+-]+$ ]] || die "unattended: bad blacklist entry '$p'"
    lines+="    \"$p\";"$'\n'
  done
  UU_BLACKLIST_LINES=${lines%$'\n'}
  put 0644 /etc/apt/apt.conf.d/20auto-upgrades < "$REPO/files/20auto-upgrades"
  install_tpl 0644 files/52vps-harden-unattended /etc/apt/apt.conf.d/52vps-harden-unattended UU_BLACKLIST_LINES
}
