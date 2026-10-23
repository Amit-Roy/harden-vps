#!/usr/bin/env bash
# vps-harden workstation: supply-chain guard rails for a dev box or container. Run as a normal user, not root.
# npm and uv release-age cooldowns + SafeDep PMG (install-time malware check). Idempotent.
set -euo pipefail

PMG_VERSION=${PMG_VERSION:-0.33.0}
COOLDOWN_DAYS=${COOLDOWN_DAYS:-7}
HOME_DIR=${HOME_DIR:-$HOME}   # override only for tests
DRY_RUN=0 SKIP_PMG=0

log() { printf '[workstation] %s\n' "$*" >&2; }
die() { printf '[workstation] ERROR: %s\n' "$*" >&2; exit 1; }

for a in "$@"; do
  case $a in
    --dry-run) DRY_RUN=1 ;;
    --skip-pmg) SKIP_PMG=1 ;;
    -h|--help) echo "Usage: workstation.sh [--dry-run] [--skip-pmg]   (env: PMG_VERSION, COOLDOWN_DAYS)"; exit 0 ;;
    *) die "unknown argument $a" ;;
  esac
done
[ "$(id -u)" != 0 ] || [ "$DRY_RUN" = 1 ] || die "run as a normal user, not root"

# set_line FILE REGEX LINE : replace the line matching REGEX or append LINE.
set_line() {
  local f=$1 re=$2 line=$3
  mkdir -p "$(dirname "$f")"; touch "$f"
  if grep -qE "$re" "$f"; then
    local tmp; tmp=$(mktemp); sed -E "s|$re.*|$line|" "$f" > "$tmp"; cat "$tmp" > "$f"; rm -f "$tmp"
  else
    printf '%s\n' "$line" >> "$f"
  fi
}

log "npm: min-release-age=$COOLDOWN_DAYS (days) in ~/.npmrc"
[ "$DRY_RUN" = 1 ] || set_line "$HOME_DIR/.npmrc" '^min-release-age[[:space:]]*=' "min-release-age=$COOLDOWN_DAYS"

log "uv: exclude-newer = \"$COOLDOWN_DAYS days\" in ~/.config/uv/uv.toml"
[ "$DRY_RUN" = 1 ] || set_line "$HOME_DIR/.config/uv/uv.toml" '^exclude-newer[[:space:]]*=' "exclude-newer = \"$COOLDOWN_DAYS days\""

[ "$SKIP_PMG" = 0 ] || { log "skipping PMG"; exit 0; }

# Pinned SafeDep PMG release, sha256-verified.
case "$(uname -m)" in
  x86_64|amd64)  asset=pmg_Linux_x86_64.tar.gz; sha=0f4afaec6800b98d7778102b67a1ee8edeb459dc853ef27f724edeaf097351fa ;;
  aarch64|arm64) asset=pmg_Linux_arm64.tar.gz;  sha=4f2c39b98d845afb0e57c29f91e966c3bc9094d534465d12aaca2833f86acdd0 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac
[ "$PMG_VERSION" = 0.33.0 ] || [ -n "${PMG_SHA256:-}" ] || die "no pinned sha256 for PMG $PMG_VERSION: set PMG_SHA256"
sha=${PMG_SHA256:-$sha}
log "pmg $PMG_VERSION -> ~/.local/bin"
if [ "$DRY_RUN" = 1 ]; then log "dry-run: stop before download"; exit 0; fi

bin="$HOME_DIR/.local/bin"; mkdir -p "$bin"
if ! { [ -x "$bin/pmg" ] && "$bin/pmg" --version 2>&1 | grep -q "$PMG_VERSION"; }; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 -o "$tmp/$asset" "https://github.com/safedep/pmg/releases/download/v$PMG_VERSION/$asset"
  echo "$sha  $tmp/$asset" | sha256sum -c --status - || die "pmg: sha256 mismatch"
  tar -xzf "$tmp/$asset" -C "$tmp" pmg
  install -m 0755 "$tmp/pmg" "$bin/pmg"
fi
export PATH="$bin:$PATH"

pmg setup install
pmg config set dependency_cooldown.days "$COOLDOWN_DAYS"
pmg config set disable_telemetry true

shims=$(find "$HOME_DIR/.pmg" "$HOME_DIR/.local/share/pmg" "$HOME_DIR/.config/pmg" -maxdepth 3 \( -name npm -o -name pip \) \( -type f -o -type l \) 2>/dev/null | head -1 | xargs -r dirname)
cat <<MSG

Done. Last step, for AI coding agents: shell aliases never reach non-interactive agent shells; PATH does.
Put the shim directory first on PATH in whatever launches your agents (service unit, wrapper script, ~/.profile):

  export PATH="${shims:-<shim dir from: pmg setup doctor>}:\$PATH"

Check with: pmg setup doctor
MSG
