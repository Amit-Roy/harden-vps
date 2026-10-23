# shellcheck shell=bash
# shellcheck disable=SC2034
# Replace (or append) a marked block in a file's content read from stdin; print the result.
merge_block() {  # merge_block FILE < block
  local file=$1 block; block=$(cat)
  local begin="# BEGIN vps-harden" end="# END vps-harden"
  {
    [ -f "$file" ] && awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$file"
    printf '%s\n%s\n%s\n' "$begin" "$block" "$end"
  }
}

mod_secscan() {
  apt_install clamav clamav-daemon clamav-freshclam nmap jq curl apparmor
  mod_enabled trivy || command -v trivy >/dev/null 2>&1 || warn "secscan: trivy not installed; enable the trivy module"
  # secscan starts its own temporary multithreaded clamd; the stock daemon would only waste RAM.
  run systemctl disable --now clamav-daemon.service clamav-daemon.socket
  run systemctl enable --now clamav-freshclam.service

  local x="" e
  for e in $CLAMAV_EXTRA_EXCLUDES; do x+="ExcludePath $e"$'\n'; done
  CLAM_EXTRA_EXCLUDES=${x%$'\n'}
  install_tpl 0644 files/clamd-secscan.conf /etc/clamav/clamd-secscan.conf CLAM_EXTRA_EXCLUDES

  local aa="${ROOT:-}/etc/apparmor.d/local/usr.sbin.clamd"
  merge_block "$aa" < "$REPO/files/apparmor-clamd.local" | put 0644 /etc/apparmor.d/local/usr.sbin.clamd
  if ! skip_system && [ -f /etc/apparmor.d/usr.sbin.clamd ]; then apparmor_parser -r /etc/apparmor.d/usr.sbin.clamd || warn "secscan: apparmor reload failed"; fi

  install_bin secscan secscan-api secscan-notify
  put 0644 /etc/systemd/system/secscan.service < "$REPO/files/systemd/secscan.service"
  install_tpl 0644 files/systemd/secscan.timer /etc/systemd/system/secscan.timer SECSCAN_CALENDAR
  run mkdir -p /var/lib/secscan
  systemd_enable secscan.timer
  cat >&2 <<'MSG'
[vps-harden] secscan installed. Optional remote control (NOT added automatically): put this one line
  in ~/.ssh/authorized_keys of a dedicated key to allow only `latest|history|get|log|status|run`:
  command="/usr/local/sbin/secscan-api",restrict ssh-ed25519 AAAA... secscan-api
  Run now: systemctl start --no-block secscan.service
  Note: nmap from the host to its own public IP bypasses the firewall (loopback path). Verify from outside: vps-harden-portcheck <ip> <port>
MSG
}
