# shellcheck shell=bash
# shellcheck disable=SC2034
mod_sysctl() {
  put 0644 /etc/sysctl.d/90-vps-harden.conf < "$REPO/files/sysctl-hardening.conf"
  run sysctl --system >/dev/null
}
