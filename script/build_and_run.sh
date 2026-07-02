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

cd "$ROOT_DIR"
if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
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
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
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
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
