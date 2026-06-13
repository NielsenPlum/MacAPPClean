#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacAppClean"
BUNDLE_ID="com.local.MacAppClean"
MIN_SYSTEM_VERSION="14.0"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [ -z "$CODE_SIGN_IDENTITY" ]; then
  CODE_SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk -F '"' '/"Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')"
fi
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# Copy icon
if [ -f "$ROOT_DIR/Sources/MacAppClean/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Sources/MacAppClean/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
elif [ -f "$ROOT_DIR/Sources/MacAppClean/Resources/AppIcon.png" ]; then
    cp "$ROOT_DIR/Sources/MacAppClean/Resources/AppIcon.png" "$APP_RESOURCES/AppIcon.png"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>MacAppClean</string>
  <key>CFBundleDisplayName</key>
  <string>MacAppClean</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>MacAppClean 需要扫描桌面中的大文件，帮助你发现可清理项目。</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>MacAppClean 需要扫描文稿中的大文件，帮助你发现可清理项目。</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>MacAppClean 需要扫描下载中的大文件，帮助你发现可清理项目。</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--verify]" >&2
    exit 2
    ;;
esac
