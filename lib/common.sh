# Installer helpers. Sourced by install.sh.
# shellcheck shell=bash
# shellcheck disable=SC2034

log()  { printf '[vps-harden] %s\n' "$*" >&2; }
warn() { printf '[vps-harden] WARN: %s\n' "$*" >&2; }
die()  { printf '[vps-harden] ERROR: %s\n' "$*" >&2; exit 1; }

# System commands (apt, systemctl, nft ...) are skipped with --dry-run or --root.
skip_system() { [ "${DRY_RUN:-0}" = 1 ] || [ -n "${ROOT:-}" ]; }
run() {
  if skip_system; then log "skip: $*"; else "$@"; fi
}

# Files are only written for real runs or when rendering into --root.
writes_files() { [ "${DRY_RUN:-0}" != 1 ] || [ -n "${ROOT:-}" ]; }

# put MODE DEST < content : write atomically, only touch the file when content changed.
put() {
  local mode=$1 dest=$2 path="${ROOT:-}$2" tmp
  if ! writes_files; then log "would write $dest"; cat >/dev/null; return 0; fi
  mkdir -p "$(dirname "$path")"
  tmp=$(mktemp "$path.XXXXXX")
  cat >"$tmp"
  chmod "$mode" "$tmp"
  if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"; chmod "$mode" "$path"
  else
    mv "$tmp" "$path"; log "wrote $dest"; CHANGED=1
  fi
}

# render FILE VAR... : print FILE with @VAR@ replaced by the value of each named variable.
render() {
  local f=$1 c v; shift
  c=$(<"$f")
  for v in "$@"; do c=${c//@${v}@/${!v-}}; done
  printf '%s\n' "$c"
}

# install_tpl MODE SRC DEST [VAR...]
install_tpl() {
  local mode=$1 src=$2 dest=$3; shift 3
  render "$REPO/$src" "$@" | put "$mode" "$dest"
}

mod_enabled() { [[ " $MODULES " == *" $1 "* ]]; }

APT_UPDATED=0
apt_install() {
  skip_system && { log "skip: apt-get install $*"; return 0; }
  if [ "$APT_UPDATED" = 0 ]; then DEBIAN_FRONTEND=noninteractive apt-get update -qq; APT_UPDATED=1; fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@"
}

# systemd_enable UNIT... : reload units, enable and (re)start them.
systemd_enable() {
  run systemctl daemon-reload
  run systemctl enable --now "$@"
}

os_codename() {
  local f="${ROOT:-}/etc/os-release"
  [ -r "$f" ] || f=/etc/os-release
  # shellcheck disable=SC1090
  ( . "$f"; echo "${VERSION_CODENAME:-}" )
}

arch_name() {  # amd64 | arm64
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "unsupported architecture $(uname -m)" ;;
  esac
}

# fetch_verified URL DEST SHA256 : download and refuse on hash mismatch.
fetch_verified() {
  local url=$1 dest=$2 sha=$3
  curl -fsSL --retry 3 -o "$dest" "$url"
  echo "$sha  $dest" | sha256sum -c --status - || { rm -f "$dest"; die "sha256 mismatch for $url"; }
}
