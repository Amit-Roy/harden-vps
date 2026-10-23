# shellcheck shell=bash
# shellcheck disable=SC2034
mod_fail2ban() {
  apt_install fail2ban python3-systemd nftables
  # Debian ships a jail.d/defaults-debian.conf that enables sshd; ours loads later (.local) and wins.
  install_tpl 0644 files/fail2ban-jail.local /etc/fail2ban/jail.d/vps-harden.local SSH_PORT
  systemd_enable fail2ban
  run systemctl reload-or-restart fail2ban
}
