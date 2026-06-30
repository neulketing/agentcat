#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/local.dooyou.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl disable "gui/$(id -u)/local.dooyou" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Removed login LaunchAgent $PLIST"
