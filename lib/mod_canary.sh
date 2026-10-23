# shellcheck shell=bash
# shellcheck disable=SC2034
# Fake AWS credentials (canarytokens.org): any use of them emails CANARY_EMAIL.
mod_canary() {
  local email=${CANARY_EMAIL:-${ALERT_TO:-}} cred=/root/.aws/credentials resp id secret region tok
  if skip_system; then log "skip: create canary AWS token (profile backup-admin)"; return 0; fi
  [ -n "$email" ] || die "canary: set CANARY_EMAIL or ALERT_TO"
  if grep -qs '^\[backup-admin\]' "$cred"; then log "canary: profile backup-admin already present"; return 0; fi
  resp=$(jq -n --arg e "$email" --arg m "vps-harden canary on $(hostname)" '{token_type:"aws_keys",email:$e,memo:$m}' \
    | curl -fsS --max-time 30 -X POST -H 'Content-Type: application/json' -d @- "$CANARY_URL") || die "canary: token request failed"
  id=$(jq -r '.aws_access_key_id // .key_id // empty' <<<"$resp")
  secret=$(jq -r '.aws_secret_access_key // .secret_access_key // empty' <<<"$resp")
  region=$(jq -r '.region // "us-east-2"' <<<"$resp")
  [ -n "$id" ] && [ -n "$secret" ] || die "canary: unexpected response (not shown, it may contain keys)"
  tok=$(jq -r '.token // empty' <<<"$resp"); tok=${tok:-$(date -u +%Y%m%dT%H%M%SZ)}
  ( umask 077
    mkdir -p /etc/vps-harden /root/.aws
    printf '%s\n' "$resp" > "/etc/vps-harden/canary-$tok.json"
    { if [ -s "$cred" ]; then echo; fi; printf '[backup-admin]\naws_access_key_id = %s\naws_secret_access_key = %s\nregion = %s\n' "$id" "$secret" "$region"; } >> "$cred" )
  chmod 600 "$cred" "/etc/vps-harden/canary-$tok.json"
  log "canary created: profile backup-admin in $cred; management JSON in /etc/vps-harden/canary-$tok.json"
}
