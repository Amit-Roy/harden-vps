# shellcheck shell=bash
# shellcheck disable=SC2034
mod_ssh() {
  local user=${SSH_TARGET_USER:-root} home keys
  if [ "$user" = root ]; then home=/root
  else home=$(getent passwd "$user" | cut -d: -f6 || true); home=${home:-/home/$user}; fi
  keys="${ROOT:-}$home/.ssh/authorized_keys"
  # Refuse to lock ourselves out.
  grep -qE '^(ssh-|ecdsa-|sk-|(command|from|restrict)[^ ]* +(ssh-|ecdsa-|sk-))' "$keys" 2>/dev/null \
    || die "ssh: no public key in $home/.ssh/authorized_keys for '$user'; add one and test a key login first"
  if ! skip_system && ! grep -qiE '^\s*Include\s+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
    die "ssh: /etc/ssh/sshd_config has no Include for sshd_config.d"
  fi
  put 0644 /etc/ssh/sshd_config.d/00-vps-harden.conf < "$REPO/files/sshd-hardening.conf"
  if ! skip_system; then
    sshd -t || { rm -f /etc/ssh/sshd_config.d/00-vps-harden.conf; die "ssh: sshd -t failed, change reverted"; }
    systemctl reload ssh
    log "ssh reloaded. Existing sessions stay open: test a NEW key login before closing this one."
  fi
}
