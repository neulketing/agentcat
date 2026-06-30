#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="dooyou"
APP_SOURCE="$ROOT_DIR/dist/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/local.dooyou.plist"

cd "$ROOT_DIR"
"$ROOT_DIR/script/build_and_run.sh" --build-only

pkill -x dooyou >/dev/null 2>&1 || true
pkill -x agentcat >/dev/null 2>&1 || true
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

mkdir -p "$(dirname "$PLIST")"
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.dooyou</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-n</string>
    <string>$APP_DEST</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl enable "gui/$(id -u)/local.dooyou"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/local.dooyou"

echo "Installed $APP_DEST"
echo "Enabled login LaunchAgent $PLIST"
