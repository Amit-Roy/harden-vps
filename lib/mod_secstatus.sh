# shellcheck shell=bash
# shellcheck disable=SC2034
mod_secstatus() {
  apt_install python3
  install_bin sec-status-api
  # Never overwrite an admin-edited config.
  if [ -e "${ROOT:-}/etc/sec-status/units.json" ]; then
    log "keep existing /etc/sec-status/units.json"
  else
    put 0644 /etc/sec-status/units.json < "$REPO/files/sec-status-units.json"
  fi
}
