# shellcheck shell=bash
# shellcheck disable=SC2034
mod_falco() {
  local prefix_cond="" p extra="" restart=0
  if ! skip_system && [ ! -f /usr/share/keyrings/falco-archive-keyring.gpg ]; then
    apt_install gnupg
    curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
      > /etc/apt/sources.list.d/falcosecurity.list
    APT_UPDATED=0
  fi
  export FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf
  apt_install falco

  for p in $FALCO_EXCLUDE_CONTAINER_PREFIXES; do
    [[ "$p" =~ ^[A-Za-z0-9._-]+$ ]] || die "falco: bad container prefix '$p'"
    prefix_cond+="${prefix_cond:+ or }container.name startswith \"$p\""
  done
  if [ -n "$prefix_cond" ]; then
    PREFIX_CONDITION=$prefix_cond
    extra=$(render "$REPO/files/falco/drift-exclude.yaml" PREFIX_CONDITION)
  fi
  EXTRA_RULES=$extra

  CHANGED=0
  put 0644 /etc/falco/config.d/90-vps-harden.yaml < "$REPO/files/falco/90-vps-harden.yaml"
  put 0644 /etc/falco/config.d/95-no-webserver.yaml < "$REPO/files/falco/95-no-webserver.yaml"
  install_tpl 0644 files/falco/falco_rules.local.yaml /etc/falco/falco_rules.local.yaml EXTRA_RULES
  [ "$CHANGED" = 0 ] || restart=1
  run systemctl enable --now falco-modern-bpf.service
  [ "$restart" = 0 ] || run systemctl restart falco-modern-bpf.service
}
