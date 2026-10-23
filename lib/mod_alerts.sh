# shellcheck shell=bash
# shellcheck disable=SC2034
mod_alerts() {
  [ "$ALERT_TRANSPORT" != none ] || warn "alerts: ALERT_TRANSPORT=none, alerts are only logged. Set a transport in the config."
  apt_install jq curl
  if mod_enabled falco || command -v falco >/dev/null 2>&1; then
    install_bin falco-alert falco-alert-flush
    local u
    for u in falco-alert.service falco-alert-flush.service falco-alert-flush.timer; do
      put 0644 "/etc/systemd/system/$u" < "$REPO/files/systemd/$u"
    done
    run mkdir -p /var/lib/falco-alert
    systemd_enable falco-alert.service falco-alert-flush.timer
  else
    log "alerts: falco not enabled, skipping the falco queue"
  fi
}
