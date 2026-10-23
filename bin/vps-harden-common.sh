# Sourced helpers shared by the installer and the installed scripts.
# shellcheck shell=bash

VH_CONF="${VPS_HARDEN_CONF:-/etc/vps-harden/config.env}"

vh_load_config() {
  # shellcheck disable=SC1090
  [ -r "$VH_CONF" ] && . "$VH_CONF"
  return 0
}

# Public interface = the one carrying the default route (override with PUBLIC_IFACE).
vh_public_iface() {
  if [ -n "${PUBLIC_IFACE:-}" ]; then echo "$PUBLIC_IFACE"; return; fi
  local d
  d=$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$d" ] || d=$(ip -o -4 route show default 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$d" ] || d=$(ip -o -6 route show default 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  echo "$d"
}

# Public IPv4 = PUBLIC_IP, else the interface address, else an external lookup when the address is private (NAT).
vh_public_ip() {
  if [ -n "${PUBLIC_IP:-}" ]; then echo "$PUBLIC_IP"; return; fi
  local i a
  i=$(vh_public_iface)
  a=$(ip -4 -o addr show dev "$i" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  if [ -z "$a" ] || [[ "$a" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; then
    a=$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || echo "$a")
  fi
  echo "$a"
}
