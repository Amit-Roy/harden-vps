# shellcheck shell=bash
# shellcheck disable=SC2034
mod_osv() {
  local v=$OSV_SCANNER_VERSION arch sha tmp
  arch=$(arch_name); sha=$(pin_sha osv-scanner "$v" "$arch")
  apt_install jq curl
  if ! skip_system; then
    if ! { command -v osv-scanner >/dev/null 2>&1 && osv-scanner --version 2>/dev/null | grep -q "$v"; }; then
      tmp=$(mktemp)
      fetch_verified "https://github.com/google/osv-scanner/releases/download/v$v/osv-scanner_linux_$arch" "$tmp" "$sha"
      install -m 0755 "$tmp" /usr/local/bin/osv-scanner; rm -f "$tmp"
    fi
  else
    log "skip: install osv-scanner $v (sha256 verified)"
  fi
  install_bin osv-malware-check
  put 0644 /etc/systemd/system/osv-malware-check.service < "$REPO/files/systemd/osv-malware-check.service"
  install_tpl 0644 files/systemd/osv-malware-check.timer /etc/systemd/system/osv-malware-check.timer OSV_CALENDAR
  systemd_enable osv-malware-check.timer
}
