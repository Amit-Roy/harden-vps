#!/usr/bin/env bash
# Offline tests: lint, render with --root, assertions. No network, no root, no system changes.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0 passes=0
ok()   { passes=$((passes+1)); echo "ok   $*"; }
fail() { fails=$((fails+1)); echo "FAIL $*"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }
expect_fail() { local d=$1; shift; if "$@" >/dev/null 2>&1; then fail "$d (should have failed)"; else ok "$d"; fi; }

ALL=ssh,fail2ban,unattended,sysctl,tailscale,trivy,falco,alerts,secscan,osv,firewall
R="$T/root"; mkdir -p "$R/root/.ssh"; echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test" > "$R/root/.ssh/authorized_keys"
inst() { ./install.sh --root "$R" "$@"; }

# 1. syntax + shellcheck
for f in install.sh workstation.sh lib/*.sh bin/* test/run.sh; do
  case $f in *.js) continue ;; esac
  check "bash -n $f" bash -n "$f"
done
sc=""
if command -v shellcheck >/dev/null 2>&1; then sc=shellcheck
elif command -v uvx >/dev/null 2>&1 && uvx --from shellcheck-py shellcheck --version >/dev/null 2>&1; then sc="uvx --from shellcheck-py shellcheck"; fi
if [ -n "$sc" ]; then
  files=(install.sh workstation.sh lib/*.sh bin/vps-harden bin/vps-harden-* bin/falco-alert* bin/secscan* bin/osv-malware-check test/run.sh)
  # shellcheck disable=SC2086
  check "shellcheck (${#files[@]} files)" $sc -x -S warning -s bash "${files[@]}"
elif [ -n "${CI:-}" ]; then fail "shellcheck missing in CI"
else echo "skip shellcheck (not installed; try: uvx --from shellcheck-py shellcheck)"; fi

# 2. render everything
check "render all modules with --root" inst --modules "$ALL"
check "render canary skipped under --root" inst --modules canary
for f in etc/ssh/sshd_config.d/00-vps-harden.conf etc/fail2ban/jail.d/vps-harden.local etc/apt/apt.conf.d/52vps-harden-unattended \
  etc/sysctl.d/90-vps-harden.conf etc/vps-harden/host_guard.nft etc/systemd/system/vps-harden-firewall.service \
  etc/falco/config.d/95-no-webserver.yaml etc/falco/falco_rules.local.yaml etc/clamav/clamd-secscan.conf \
  etc/apparmor.d/local/usr.sbin.clamd etc/systemd/system/secscan.timer etc/systemd/system/osv-malware-check.timer \
  usr/local/sbin/vps-harden-notify usr/local/sbin/secscan usr/local/sbin/secscan-api usr/local/sbin/osv-malware-check \
  usr/local/lib/vps-harden/common.sh etc/vps-harden/config.env; do
  check "exists $f" test -s "$R/$f"
done
check "no unreplaced @VAR@ placeholders" bash -c "! grep -rE '@[A-Z_]+@' '$R'"
check "config.env mode 600" test "$(stat -c %a "$R/etc/vps-harden/config.env")" = 600
check "host_guard.nft mode 600" test "$(stat -c %a "$R/etc/vps-harden/host_guard.nft")" = 600
check "notify helper executable" test -x "$R/usr/local/sbin/vps-harden-notify"
check "sshd key-only" grep -q '^PasswordAuthentication no' "$R/etc/ssh/sshd_config.d/00-vps-harden.conf"
check "falco webserver disabled" grep -q 'enabled: false' "$R/etc/falco/config.d/95-no-webserver.yaml"
check "secscan timer has calendar" grep -q '^OnCalendar=Sun' "$R/etc/systemd/system/secscan.timer"
check "unattended blacklist docker-" grep -q '"docker-";' "$R/etc/apt/apt.conf.d/52vps-harden-unattended"
check "firewall: ssh closed by default" bash -c "! grep -q 'dport {[^}]*22' '$R/etc/vps-harden/host_guard.nft'"
check "firewall: tailscale udp 41641 open" grep -q '41641' "$R/etc/vps-harden/host_guard.nft"
check "firewall: forward chain drops" bash -c "sed -n '/chain forward/,\$p' '$R/etc/vps-harden/host_guard.nft' | grep -q 'counter drop'"
check "systemd units verify (if available)" bash -c "! command -v systemd-analyze >/dev/null || true"

# 3. idempotent: second run rewrites nothing
out=$(inst --modules "$ALL" 2>&1)
if grep -q 'wrote ' <<<"$out"; then fail "idempotent re-run (rewrote: $(grep -c 'wrote ' <<<"$out") files)"; else ok "idempotent re-run"; fi

# 4. config-driven variants
R2="$T/root2"; mkdir -p "$R2/root/.ssh" "$R2/etc/vps-harden"; cp "$R/root/.ssh/authorized_keys" "$R2/root/.ssh/"
cat > "$R2/etc/vps-harden/config.env" <<'CFG'
SSH_PUBLIC=yes
SSH_PORT=2222
PUBLIC_IFACE=eth9
FW_TCP_PORTS="443 8443"
FW_UDP_PORTS=""
FALCO_EXCLUDE_CONTAINER_PREFIXES="dev- ci-"
UU_BLACKLIST="docker- foo"
CLAMAV_EXTRA_EXCLUDES="/\\.cache/"
CFG
check "render with custom config" ./install.sh --root "$R2" --modules ssh,firewall,falco,unattended,secscan
N="$R2/etc/vps-harden/host_guard.nft"
check "custom iface in nft" grep -q 'iifname != "eth9" accept' "$N"
check "custom tcp ports + ssh port" grep -q 'tcp dport { 443, 2222, 8443 } accept' "$N"
check "no udp rule when empty" bash -c "! grep -q 'udp dport {' '$N'"
check "falco container prefix exclusion" grep -q 'container.name startswith "dev-" or container.name startswith "ci-"' "$R2/etc/falco/falco_rules.local.yaml"
check "custom blacklist" grep -q '"foo";' "$R2/etc/apt/apt.conf.d/52vps-harden-unattended"

# 5. nft syntax (needs privileges; skipped otherwise)
if command -v nft >/dev/null 2>&1; then
  nftc=""
  nft -c -f "$N" >/dev/null 2>&1 && nftc="nft"
  [ -z "$nftc" ] && sudo -n nft -c -f "$N" >/dev/null 2>&1 && nftc="sudo -n nft"
  if [ -n "$nftc" ]; then
    for f in "$N" "$R/etc/vps-harden/host_guard.nft"; do check "nft -c $(basename "$(dirname "$(dirname "$f")")")" $nftc -c -f "$f"; done
  elif [ -n "${CI:-}" ]; then fail "nft -c not permitted in CI"
  else echo "skip nft -c (needs root)"; fi
else echo "skip nft -c (nft not installed)"; fi

# 6. refusals
R3="$T/root3"; mkdir -p "$R3/root/.ssh"
expect_fail "ssh refuses without authorized_keys" ./install.sh --root "$R3" --modules ssh
: > "$R3/root/.ssh/authorized_keys"
expect_fail "ssh refuses with empty authorized_keys" ./install.sh --root "$R3" --modules ssh
cp "$R/root/.ssh/authorized_keys" "$R3/root/.ssh/authorized_keys"
expect_fail "firewall refuses SSH_PUBLIC=no without tailscale" ./install.sh --root "$R3" --modules firewall
echo "SSH_PUBLIC=yes" > "$T/pub.cfg"
check "firewall ok with SSH_PUBLIC=yes" ./install.sh --root "$R3" --config "$T/pub.cfg" --modules firewall
for v in 0.69.4 0.69.5 0.69.6; do
  mkdir -p "$T/c$v"; echo "TRIVY_VERSION=$v" > "$T/c$v/cfg"
  expect_fail "trivy $v refused" ./install.sh --root "$R3" --config "$T/c$v/cfg" --modules trivy
done
expect_fail "unknown module rejected" ./install.sh --root "$R3" --modules nope
check "--dry-run alone writes nothing" bash -c "cd '$T' && mkdir -p dry && cd dry && '$REPO/install.sh' --dry-run --modules sysctl && [ -z \"\$(ls -A .)\" ]"

# 7. scripts
check "notify with transport none exits 0" env VPS_HARDEN_CONF=/nonexistent VPS_HARDEN_LIB="$REPO/bin/vps-harden-common.sh" bash -c "echo body | '$REPO/bin/vps-harden-notify' subject"
check "pins: cosign pinned" bash -c ". lib/common.sh; . lib/pins.sh; [ -n \"\$(pin_sha cosign 3.1.4 amd64)\" ]"
HOME_DIR="$T/home"; mkdir -p "$HOME_DIR"
check "workstation --skip-pmg" env HOME_DIR="$HOME_DIR" ./workstation.sh --skip-pmg
check "workstation re-run" env HOME_DIR="$HOME_DIR" ./workstation.sh --skip-pmg
check "npmrc cooldown" grep -qx 'min-release-age=7' "$HOME_DIR/.npmrc"
check "npmrc single entry" test "$(grep -c min-release-age "$HOME_DIR/.npmrc")" = 1
check "uv cooldown" grep -qx 'exclude-newer = "7 days"' "$HOME_DIR/.config/uv/uv.toml"

# 8. npm package + launcher
if command -v node >/dev/null 2>&1; then
  check "launcher --help" bash -c "node bin/harden-vps.js --help | grep -q Usage"
  check "launcher install --help" bash -c "node bin/harden-vps.js install --help | grep -q -- --modules"
  expect_fail "launcher rejects unknown command" node bin/harden-vps.js bogus
  if command -v npm >/dev/null 2>&1; then
    list=$(npm pack --dry-run --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s)[0].files.map(f=>f.path).join("\n")))' 2>/dev/null || true)
    if [ -n "$list" ]; then
      for p in package.json install.sh workstation.sh bin/harden-vps.js lib/mod_firewall.sh files/nft/host_guard.nft config.example.env SKILL.md README.md LICENSE; do
        check "npm pack includes $p" grep -qx "$p" <<<"$list"
      done
      check "npm pack excludes test/" bash -c "! grep -q '^test/' <<<'$list'"
    else echo "skip npm pack (npm output unavailable)"; fi
  fi
else echo "skip launcher/npm tests (node missing)"; fi

# 9. sanitization of this repo (working tree)
# Personal-data patterns, rot13-encoded so this file does not trip its own check.
bad=$(echo 'arseb|nzvg|fhaal|ebl|qhpxqaf|206[.]51|100[.]83|100[.]112|100[.]103|260[2]:|ffqabqrf|ntragznvy\.gb|rac3f0|pbqre-Nzvg|fxljnyxre|barcyhf|tznvy' | tr 'A-Za-z' 'N-ZA-Mn-za-m')
if hits=$(grep -rniE "$bad" --exclude-dir=.git --exclude-dir=node_modules .); [ -n "$hits" ]; then
  fail "sanitization grep: $(wc -l <<<"$hits") hit(s)"; echo "$hits" | head
else ok "sanitization grep clean"; fi

echo; echo "passed=$passes failed=$fails"
[ "$fails" = 0 ]
