# Pinned SHA-256 of release artifacts downloaded without a signature. Override with <TOOL>_SHA256 for other versions.
# shellcheck shell=bash
# shellcheck disable=SC2034

pin_sha() {  # pin_sha TOOL VERSION ARCH
  local tool=$1 ver=$2 arch=$3 ov
  ov="${tool^^}_SHA256"; ov=${ov//-/_}
  if [ -n "${!ov:-}" ]; then echo "${!ov}"; return; fi
  case "$tool $ver $arch" in
    "cosign 3.1.4 amd64")        echo 424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa ;;
    "cosign 3.1.4 arm64")        echo ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2 ;;
    "osv-scanner 2.7.0 amd64")   echo 160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b ;;
    "osv-scanner 2.7.0 arm64")   echo 4061ef4c021ed3c47f203b818f337e351336cc5cd67c0274fc36bd1dfc728dd7 ;;
    *) die "no pinned sha256 for $tool $ver ($arch): set ${ov} in the config after checking the release checksums" ;;
  esac
}
