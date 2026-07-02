#!/bin/sh
# dooyou statusline wrapper — renderer-agnostic. Captures per-account rate_limits
# for the dooyou app (background, non-blocking), then renders whatever statusline
# this machine already had, unchanged. Works with or without OMC.
#
# Render priority: preserved original (~/.dooyou/inner-statusline) > OMC HUD >
# a minimal built-in line (dir · model). Capture always runs regardless.
# Wired automatically by install-statusline.sh (also invoked from deploy-fleet.sh).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
in=$(cat)
NODE="$(command -v node 2>/dev/null)"

# 1) capture — best-effort, never blocks or affects the rendered line
[ -n "$NODE" ] && printf '%s' "$in" | "$NODE" "$HOME/.dooyou/bin/capture-limits.mjs" >/dev/null 2>&1 &

# 2) render the machine's real statusline
INNER="$HOME/.dooyou/inner-statusline"
OMC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hud/omc-hud.mjs"
if [ -s "$INNER" ]; then
  printf '%s' "$in" | sh -c "$(cat "$INNER")"
elif [ -f "$OMC" ] && [ -n "$NODE" ]; then
  printf '%s' "$in" | "$NODE" "$OMC"
elif [ -n "$NODE" ]; then
  # machine had no statusline — show a clean minimal default instead of a blank line
  printf '%s' "$in" | "$NODE" -e 'try{const d=JSON.parse(require("fs").readFileSync(0,"utf8"));const m=d.model?.display_name||d.model?.id||"";const dir=(d.workspace?.current_dir||d.cwd||"").split("/").pop()||"";process.stdout.write([dir,m].filter(Boolean).join("  ·  "))}catch{}'
fi
