#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <ssh-host> [ssh-user]" >&2
  echo "example: $0 100.104.252.57 osihwan" >&2
  exit 2
fi

HOST="$1"
USER_NAME="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="$ROOT_DIR/dist/release/dooyou-macos.zip"
REMOTE="/tmp/dooyou-macos.zip"
SSH_TARGET="$HOST"
if [[ -n "$USER_NAME" ]]; then
  SSH_TARGET="$USER_NAME@$HOST"
fi

cd "$ROOT_DIR"
"$ROOT_DIR/script/package_release.sh"

scp "$ZIP_PATH" "$SSH_TARGET:$REMOTE"
ssh "$SSH_TARGET" '
set -euo pipefail
rm -rf /tmp/dooyou-install
mkdir -p /tmp/dooyou-install
ditto -x -k /tmp/dooyou-macos.zip /tmp/dooyou-install
INSTALLER="$(find /tmp/dooyou-install -name install-dooyou.command -type f | head -1)"
if [[ -z "$INSTALLER" ]]; then
  echo "install-dooyou.command not found in package" >&2
  exit 1
fi
"$INSTALLER"
'
