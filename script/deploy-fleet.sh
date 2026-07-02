#!/usr/bin/env bash
# Sync dooyou fleet helpers from canonical dooyou-bin/ to every remote in
# ~/.dooyou/fleet.json. Run from the hub after editing quota / probes.
# Replaces hand-run scp-per-machine. `fleet` itself stays hub-only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dooyou-bin"
CFG="$HOME/.dooyou/fleet.json"
FILES=(quota probe-limits.mjs capture-limits.mjs statusline-wrap.sh install-statusline.sh)

# Hub: refresh local ~/.dooyou/bin (+ fleet) from canonical.
mkdir -p "$HOME/.dooyou/bin"
for f in "${FILES[@]}" fleet; do
  cp "$SRC/$f" "$HOME/.dooyou/bin/$f"
  chmod +x "$HOME/.dooyou/bin/$f" 2>/dev/null || true
done
ln -sf "$HOME/.dooyou/bin/quota" "$HOME/.local/bin/quota"
ln -sf "$HOME/.dooyou/bin/fleet" "$HOME/.local/bin/fleet"
sh "$HOME/.dooyou/bin/install-statusline.sh" | sed 's/^/[hub] statusline: /'
echo "[hub] $(hostname) synced"

[ -f "$CFG" ] || { echo "no fleet config at $CFG"; exit 0; }

# Remotes: pull ssh targets from fleet.json, scp helpers to each.
node -e 'JSON.parse(require("fs").readFileSync(process.env.HOME+"/.dooyou/fleet.json","utf8")).filter(n=>n.ssh).forEach(n=>console.log(n.ssh))' \
| while read -r t; do
  [ -z "$t" ] && continue
  # -n on ssh: don't let ssh read the while-loop's piped stdin (else it eats the
  # remaining targets and only the first machine syncs).
  if ! ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$t" 'mkdir -p "$HOME/.dooyou/bin" "$HOME/.local/bin"' 2>/dev/null; then
    echo "[skip] $t unreachable"; continue
  fi
  for f in "${FILES[@]}"; do scp -q -o BatchMode=yes "$SRC/$f" "$t:.dooyou/bin/$f"; done
  ssh -n -o BatchMode=yes "$t" 'chmod +x "$HOME/.dooyou/bin/quota" "$HOME/.dooyou/bin/statusline-wrap.sh" "$HOME/.dooyou/bin/install-statusline.sh" 2>/dev/null; ln -sf "$HOME/.dooyou/bin/quota" "$HOME/.local/bin/quota"; sh "$HOME/.dooyou/bin/install-statusline.sh"' \
    | sed "s/^/[ok]   $t statusline: /"
  echo "[ok]   $t synced"
done
echo "done."
