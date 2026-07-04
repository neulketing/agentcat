#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PACKAGE_PRODUCT="dooyou"
PROCESS_NAME="dooyou"
APP_NAME="dooyou"
BUNDLE_ID="local.dooyou"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PACKAGE_PRODUCT"
INFO_PLIST="$APP_CONTENTS/Info.plist"

LAUNCH_LABEL="local.dooyou"
LAUNCH_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

cd "$ROOT_DIR"
if [[ "$MODE" == "--install" || "$MODE" == "install" ]]; then
  exec "$ROOT_DIR/script/install_login_item.sh"
fi

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  # KeepAlive 런치에이전트가 있으면 먼저 bootout — 안 하면 pkill 순간 launchd가 되살려
  # open -n과 합쳐 2중 인스턴스가 된다 (2026-07-03 실사고: 메뉴바 두유 2개).
  launchctl bootout "$GUI_DOMAIN/$LAUNCH_LABEL" >/dev/null 2>&1 || true
  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
  pkill -x agentcat >/dev/null 2>&1 || true
fi

# ponytail: universal binary so the app runs on Intel Macs too (arm64 + x86_64).
# Built per-arch then lipo'd, because multi-arch `swift build` needs full Xcode
# while this path works with Command Line Tools alone. For an arm64-only build,
# replace this block with `swift build`.
swift build --arch arm64
swift build --arch x86_64
BUILD_DIR="$(swift build --arch arm64 --show-bin-path)"
X86_DIR="$(swift build --arch x86_64 --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/${PACKAGE_PRODUCT}-universal"
lipo -create "$BUILD_DIR/$PACKAGE_PRODUCT" "$X86_DIR/$PACKAGE_PRODUCT" -output "$BUILD_BINARY"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
find "$BUILD_DIR" -maxdepth 1 -name "${PACKAGE_PRODUCT}_*.bundle" -exec cp -R {} "$APP_RESOURCES/" \;

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PACKAGE_PRODUCT</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  # 런치에이전트가 설치돼 있으면 launchd 관리 인스턴스로 단일화(bootstrap이 RunAtLoad 기동).
  # open -n은 강제 새 인스턴스라 KeepAlive와 만나면 2중 실행이 된다.
  if [[ -f "$LAUNCH_PLIST" ]]; then
    launchctl bootstrap "$GUI_DOMAIN" "$LAUNCH_PLIST" 2>/dev/null \
      || launchctl kickstart -k "$GUI_DOMAIN/$LAUNCH_LABEL"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

case "$MODE" in
  --build-only|build-only)
    ;;
  --install|install)
    # 정식 배포 경로: dist → /Applications 교체 후 launchd 관리 인스턴스 재기동.
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" /Applications/
    open_app
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--install|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
