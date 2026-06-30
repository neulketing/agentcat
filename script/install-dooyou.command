#!/usr/bin/env bash
set -euo pipefail

APP_NAME="dooyou"
BUNDLE_ID="local.dooyou"
APP_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

say_step() {
  printf '\n[%s] %s\n' "$APP_NAME" "$1"
}

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Cannot find $APP_NAME.app next to this installer."
  echo "Unzip dooyou-macos.zip first, then run install-dooyou.command from that folder."
  exit 1
fi

say_step "Requesting administrator permission for /Applications install and Remote Login."
sudo -v

say_step "Installing $APP_DEST."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x agentcat >/dev/null 2>&1 || true
sudo rm -rf "$APP_DEST"
sudo cp -R "$APP_SOURCE" "$APP_DEST"
sudo chown -R root:wheel "$APP_DEST"
sudo xattr -dr com.apple.quarantine "$APP_DEST" >/dev/null 2>&1 || true

say_step "Enabling launch at login for the current user."
mkdir -p "$(dirname "$PLIST")"
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BUNDLE_ID</string>
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
launchctl enable "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1 || true

say_step "Enabling Remote Login for future automatic installs."
sudo dseditgroup -o create -q com.apple.access_ssh >/dev/null 2>&1 || true
sudo dseditgroup -o edit -a "$USER" -t user com.apple.access_ssh >/dev/null 2>&1 || true
if ! sudo systemsetup -f -setremotelogin on >/dev/null 2>&1; then
  sudo launchctl enable system/com.openssh.sshd >/dev/null 2>&1 || true
  sudo launchctl kickstart -k system/com.openssh.sshd >/dev/null 2>&1 || true
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist >/dev/null 2>&1 || true
fi

REMOTE_LOGIN_STATUS="$(sudo systemsetup -getremotelogin 2>/dev/null || true)"
TAILSCALE_IP="$(command -v tailscale >/dev/null 2>&1 && tailscale ip -4 2>/dev/null | head -1 || true)"

say_step "Launching $APP_NAME."
/usr/bin/open -n "$APP_DEST" || true

echo
echo "Installed: $APP_DEST"
echo "LaunchAgent: $PLIST"
echo "Remote Login: ${REMOTE_LOGIN_STATUS:-check System Settings > General > Sharing > Remote Login}"
if [[ -n "$TAILSCALE_IP" ]]; then
  echo "Tailscale SSH target: $USER@$TAILSCALE_IP"
else
  echo "Tailscale IP not found in PATH. Check the Tailscale app if needed."
fi
echo
echo "You can close this window."
