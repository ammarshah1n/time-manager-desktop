#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/Timed.app"
EXECUTABLE_NAME="timed"
ICON_SOURCE="$ROOT_DIR/docs/timed-logo.svg"
ICONSET_SOURCE="$ROOT_DIR/Assets.xcassets/AppIcon.appiconset"
ICON_NAME="Timed"

swift build -c release
bash "$ROOT_DIR/scripts/render_app_icons.sh"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/time-manager-desktop" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

if [[ -d "$ICONSET_SOURCE" ]]; then
  ICONSET_DIR="$(mktemp -d)"
  mkdir -p "$ICONSET_DIR/${ICON_NAME}.iconset"
  cp "$ICONSET_SOURCE"/icon_*.png "$ICONSET_DIR/${ICON_NAME}.iconset/"
  iconutil -c icns "$ICONSET_DIR/${ICON_NAME}.iconset" -o "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
  rm -rf "$ICONSET_DIR"
elif [[ -f "$ICON_SOURCE" ]]; then
  ICONSET_DIR="$(mktemp -d)"
  mkdir -p "$ICONSET_DIR/${ICON_NAME}.iconset"
  for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
  do
    size="${spec%% *}"
    file="${spec#* }"
    sips -z "$size" "$size" -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/${ICON_NAME}.iconset/$file" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR/${ICON_NAME}.iconset" -o "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
  rm -rf "$ICONSET_DIR"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>timed</string>
  <key>CFBundleIdentifier</key>
  <string>com.ammarshahin.timed</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Timed</string>
  <key>CFBundleDisplayName</key>
  <string>Timed</string>
  <key>CFBundleIconFile</key>
  <string>Timed</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
  <string>Timed writes your approved study blocks to Apple Calendar so they sync to your iPhone.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Timed may automate calendar and local productivity workflows on your Mac.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Packaged $APP_DIR"
