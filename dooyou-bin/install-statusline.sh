#!/bin/sh
# Auto-connect dooyou rate-limit capture into this machine's claude statusLine.
# Detects whatever statusLine was already configured, preserves it as the inner
# renderer, and points statusLine at statusline-wrap.sh. Idempotent — safe to
# re-run. Works whether or not OMC is present. Invoked per-machine by deploy-fleet.sh.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
NODE="$(command -v node 2>/dev/null)" || true
[ -z "$NODE" ] && { echo "install-statusline: node not found, skipping"; exit 0; }

"$NODE" <<'JS'
const fs = require('fs'), path = require('path');
const H = process.env.HOME;
const sp = path.join(H, '.claude', 'settings.json');
const WRAP = 'sh ' + path.join(H, '.dooyou', 'bin', 'statusline-wrap.sh');
const innerPath = path.join(H, '.dooyou', 'inner-statusline');

let s = {};
try { s = JSON.parse(fs.readFileSync(sp, 'utf8')); } catch {}
const cur = (s.statusLine && s.statusLine.command) || '';

if (cur.includes('statusline-wrap.sh')) { console.log('already wrapped — ok'); process.exit(0); }

fs.mkdirSync(path.join(H, '.dooyou'), { recursive: true });
// preserve the original renderer (if any) so the wrap forwards to it unchanged
if (cur) fs.writeFileSync(innerPath, cur + '\n');
else { try { fs.unlinkSync(innerPath); } catch {} }

s.statusLine = { type: 'command', command: WRAP };
fs.mkdirSync(path.dirname(sp), { recursive: true });
fs.writeFileSync(sp, JSON.stringify(s, null, 2) + '\n');
console.log('wrapped (inner: ' + (cur || '(none — minimal default)') + ')');
JS
