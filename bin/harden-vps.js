#!/usr/bin/env node
'use strict';
// Launcher: npx harden-vps install|workstation|<helper> [args...]. Runs the bundled shell scripts.
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const [cmd, ...rest] = process.argv.slice(2);

const usage = `harden-vps: one-command Linux VPS security hardening (Debian)

Usage:
  npx harden-vps install [--modules a,b] [--dry-run] [--root DIR] [--config FILE] [--firewall-auto-confirm]
  npx harden-vps workstation [--dry-run] [--skip-pmg]
  npx harden-vps --help

'install' must run as root on the VPS (sudo npx harden-vps install ...).
'workstation' runs as a normal user on your dev box or container.
Docs: README.md in the package, SKILL.md for coding agents.`;

function run(script, args) {
  const r = spawnSync('bash', [path.join(root, script), ...args], { stdio: 'inherit' });
  if (r.error) {
    console.error(`harden-vps: cannot run bash: ${r.error.message}`);
    process.exit(127);
  }
  process.exit(r.status === null ? 1 : r.status);
}

if (!cmd || cmd === '-h' || cmd === '--help' || cmd === 'help') {
  console.log(usage);
} else if (cmd === 'install') {
  run('install.sh', rest);
} else if (cmd === 'workstation') {
  run('workstation.sh', rest);
} else if (cmd.startsWith('-')) {
  run('install.sh', [cmd, ...rest]);
} else {
  console.error(`harden-vps: unknown command '${cmd}'\n\n${usage}`);
  process.exit(2);
}
