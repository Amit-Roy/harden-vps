# Always installed: shared lib, notify helper, CLI, config template.
# shellcheck shell=bash
# shellcheck disable=SC2034

install_bin() {  # install_bin NAME... : copy bin/NAME to /usr/local/sbin
  local n
  for n in "$@"; do put 0755 "/usr/local/sbin/$n" < "$REPO/bin/$n"; done
}

core_install() {
  if writes_files; then
    mkdir -p "$ROOT/etc/vps-harden"; chmod 700 "$ROOT/etc/vps-harden"
    if [ ! -f "$ROOT/etc/vps-harden/config.env" ]; then
      put 0600 /etc/vps-harden/config.env < "$REPO/config.example.env"
      log "created /etc/vps-harden/config.env (mode 600): edit it, then re-run"
    fi
  fi
  put 0644 /usr/local/lib/vps-harden/common.sh < "$REPO/bin/vps-harden-common.sh"
  install_bin vps-harden vps-harden-notify vps-harden-safe-restart vps-harden-portcheck
  apt_install curl jq ca-certificates
}
