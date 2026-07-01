#!/bin/sh
# dooyou statusline wrapper: capture rate_limits for the dooyou app (background,
# non-blocking) then render the real OMC HUD unchanged. Terminal UX is identical;
# dooyou just gains a live per-account limits feed.
in=$(cat)
printf '%s' "$in" | node "$HOME/.dooyou/bin/capture-limits.mjs" >/dev/null 2>&1 &
printf '%s' "$in" | node "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hud/omc-hud.mjs"
