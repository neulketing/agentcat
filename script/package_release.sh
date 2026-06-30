#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="dooyou"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-macos.zip"
PAYLOAD_DIR="$RELEASE_DIR/$APP_NAME-macos"

cd "$ROOT_DIR"
"$ROOT_DIR/script/build_and_run.sh" --build-only

export COPYFILE_DISABLE=1
rm -rf "$RELEASE_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -X -R "$APP_BUNDLE" "$PAYLOAD_DIR/$APP_NAME.app"
cp "$ROOT_DIR/script/install-dooyou.command" "$PAYLOAD_DIR/install-dooyou.command"
chmod +x "$PAYLOAD_DIR/install-dooyou.command"
cat >"$PAYLOAD_DIR/INSTALL.txt" <<TXT
DOOYOU install

1. Unzip dooyou-macos.zip.
2. Double-click install-dooyou.command.
3. Enter the Mac administrator password when Terminal asks.

The installer copies dooyou.app to /Applications, registers a per-user
LaunchAgent with KeepAlive, and enables Remote Login for this macOS user so
future updates can be installed remotely.

To stop dooyou permanently on this Mac, unload the LaunchAgent with:

  launchctl bootout "gui/\$(id -u)" "\$HOME/Library/LaunchAgents/local.dooyou.plist" 2>/dev/null || true
  launchctl disable "gui/\$(id -u)/local.dooyou" 2>/dev/null || true
  rm -f "\$HOME/Library/LaunchAgents/local.dooyou.plist"

If macOS blocks the command, open System Settings > Privacy & Security and allow it.
TXT

ditto -c -k --norsrc --keepParent "$PAYLOAD_DIR" "$ZIP_PATH"

codesign -dvvv "$APP_BUNDLE" >/tmp/dooyou-codesign.txt 2>&1 || true
spctl -a -vv "$APP_BUNDLE" >/tmp/dooyou-spctl.txt 2>&1 || true

echo "Packaged $ZIP_PATH"
echo "Signing details: /tmp/dooyou-codesign.txt"
echo "Gatekeeper check: /tmp/dooyou-spctl.txt"
