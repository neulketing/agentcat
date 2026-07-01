#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="dooyou"
APP_SOURCE="$ROOT_DIR/dist/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DEST/Contents/MacOS/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/local.dooyou.plist"
LOG_DIR="$HOME/Library/Logs/dooyou"

cd "$ROOT_DIR"
"$ROOT_DIR/script/build_and_run.sh" --build-only

pkill -x dooyou >/dev/null 2>&1 || true
pkill -x agentcat >/dev/null 2>&1 || true
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

# Deploy the helpers (statusline capture / limits probe / quota reader) to ~/.dooyou/bin.
BIN_DEST="$HOME/.dooyou/bin"
if [ -d "$ROOT_DIR/dooyou-bin" ]; then
  mkdir -p "$BIN_DEST"
  cp "$ROOT_DIR/dooyou-bin/"*.mjs "$ROOT_DIR/dooyou-bin/"*.sh "$ROOT_DIR/dooyou-bin/quota" "$BIN_DEST/" 2>/dev/null || true
  chmod +x "$BIN_DEST/statusline-wrap.sh" "$BIN_DEST/quota" 2>/dev/null || true
  # Expose `quota` in PATH so any agent (GJC, Hermes, …) can read dooyou's limits.
  mkdir -p "$HOME/.local/bin" && ln -sf "$BIN_DEST/quota" "$HOME/.local/bin/quota"
fi

# Deploy the dooyou-quota skill into every agent CLI that discovers SKILL.md skills
# (only where the CLI is actually installed — i.e., its config dir exists).
SKILL_SRC="$ROOT_DIR/dooyou-bin/skills/dooyou-quota/SKILL.md"
if [ -f "$SKILL_SRC" ]; then
  for base in "$HOME/.claude" "$HOME/.codex" "$HOME/.gjc" "$HOME/.hermes" "$HOME/.config/opencode"; do
    [ -d "$base" ] || continue
    mkdir -p "$base/skills/dooyou-quota"
    cp "$SKILL_SRC" "$base/skills/dooyou-quota/SKILL.md"
  done
fi

mkdir -p "$(dirname "$PLIST")"
mkdir -p "$LOG_DIR"
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.dooyou</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl enable "gui/$(id -u)/local.dooyou"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/local.dooyou"

echo "Installed $APP_DEST"
echo "Enabled login LaunchAgent $PLIST"
echo "DOOYOU is now launchd-managed and will relaunch if it exits."
echo
echo "For live Claude limits, set each Claude Code config's statusLine command to:"
echo "  sh \$HOME/.dooyou/bin/statusline-wrap.sh"
echo "(wraps the existing HUD; captures rate_limits for dooyou). See dooyou-bin/README.md."
