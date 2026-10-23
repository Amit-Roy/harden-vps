# shellcheck shell=bash
# shellcheck disable=SC2034
install_cosign() {
  local arch sha
  command -v cosign >/dev/null 2>&1 && cosign version 2>/dev/null | grep -q "v$COSIGN_VERSION" && return 0
  arch=$(arch_name); sha=$(pin_sha cosign "$COSIGN_VERSION" "$arch")
  skip_system && { log "skip: install cosign $COSIGN_VERSION"; return 0; }
  local tmp; tmp=$(mktemp)
  fetch_verified "https://github.com/sigstore/cosign/releases/download/v$COSIGN_VERSION/cosign-linux-$arch" "$tmp" "$sha"
  install -m 0755 "$tmp" /usr/local/bin/cosign; rm -f "$tmp"
}

mod_trivy() {
  local v=$TRIVY_VERSION
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "trivy: bad version '$v'"
  # GHSA-69fq-xp46-6x23: compromised releases.
  case $v in 0.69.4|0.69.5|0.69.6) die "trivy: version $v is blocked (GHSA-69fq-xp46-6x23); choose another" ;; esac
  if ! skip_system && dpkg-query -W -f='${Version}' trivy 2>/dev/null | grep -qx "$v"; then
    log "trivy $v already installed"; apt-mark hold trivy >/dev/null; return 0
  fi
  install_cosign
  skip_system && { log "skip: install trivy $v (sha256 + cosign verified, held)"; return 0; }
  local arch deb base tmp want
  arch=$(arch_name); deb="trivy_${v}_Linux-$([ "$arch" = amd64 ] && echo 64bit || echo ARM64).deb"
  base="https://github.com/aquasecurity/trivy/releases/download/v$v"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/$deb" "$base/$deb"
  curl -fsSL -o "$tmp/checksums.txt" "$base/trivy_${v}_checksums.txt"
  curl -fsSL -o "$tmp/checksums.sigstore.json" "$base/trivy_${v}_checksums.txt.sigstore.json"
  cosign verify-blob --bundle "$tmp/checksums.sigstore.json" \
    --certificate-identity-regexp "^https://github\\.com/aquasecurity/trivy/\\.github/workflows/.+@refs/tags/v$v\$" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$tmp/checksums.txt" \
    || die "trivy: cosign signature of the checksums file did not verify"
  want=$(awk -v f="$deb" '$2==f{print $1}' "$tmp/checksums.txt")
  [ -n "$want" ] || die "trivy: $deb not in checksums file"
  [ -z "${TRIVY_SHA256:-}" ] || [ "$TRIVY_SHA256" = "$want" ] || die "trivy: TRIVY_SHA256 pin does not match the signed checksums"
  echo "$want  $tmp/$deb" | sha256sum -c --status - || die "trivy: sha256 mismatch"
  dpkg -i "$tmp/$deb"
  apt-mark hold trivy >/dev/null
  log "trivy $v installed and held"
}
