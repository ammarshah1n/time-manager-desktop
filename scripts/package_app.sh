#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist.noindex/Timed.app"
EXECUTABLE_NAME="timed"
ICON_SOURCE="$ROOT_DIR/docs/timed-logo.svg"
ICONSET_SOURCE="$ROOT_DIR/Assets.xcassets/AppIcon.appiconset"
ICON_NAME="Timed"
CODESIGN_IDENTITY="${TIMED_CODESIGN_IDENTITY:--}"

codesign_bundle() {
  if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    codesign --force --deep --options runtime --timestamp "$@"
  else
    codesign --force --deep "$@"
  fi
}

swift build -c release
bash "$ROOT_DIR/scripts/render_app_icons.sh"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/time-manager-desktop" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
# Embed MSAL.framework for OAuth
MSAL_SRC="$ROOT_DIR/.build/artifacts/microsoft-authentication-library-for-objc/MSAL/MSAL.xcframework/macos-arm64_x86_64/MSAL.framework"
if [[ ! -d "$MSAL_SRC" ]]; then
  MSAL_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/MSAL.framework"
fi
if [[ -d "$MSAL_SRC" ]]; then
  mkdir -p "$APP_DIR/Contents/Frameworks"
  cp -R "$MSAL_SRC" "$APP_DIR/Contents/Frameworks/MSAL.framework"
  install_name_tool -add_rpath @loader_path/../Frameworks "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true
  echo "Embedded MSAL.framework"
else
  echo "WARNING: MSAL.framework not found — OAuth will not work"
fi

# Embed LiveKitWebRTC.framework — transitive dep of ElevenLabs SDK's voice stack.
# Without this, the binary dyld-crashes on launch because the ElevenLabs
# Conversation import pulls in LiveKit at runtime.
LIVEKIT_SRC="$ROOT_DIR/.build/artifacts/webrtc-xcframework/LiveKitWebRTC/LiveKitWebRTC.xcframework/macos-arm64_x86_64/LiveKitWebRTC.framework"
if [[ ! -d "$LIVEKIT_SRC" ]]; then
  LIVEKIT_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/LiveKitWebRTC.framework"
fi
if [[ -d "$LIVEKIT_SRC" ]]; then
  mkdir -p "$APP_DIR/Contents/Frameworks"
  cp -R "$LIVEKIT_SRC" "$APP_DIR/Contents/Frameworks/LiveKitWebRTC.framework"
  echo "Embedded LiveKitWebRTC.framework"
else
  echo "WARNING: LiveKitWebRTC.framework not found — voice check-in will crash on launch"
fi
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
  <string>0.2.0</string>
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
  <key>NSMicrophoneUsageDescription</key>
  <string>Timed uses your microphone for voice capture during the morning planning interview.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Timed uses speech recognition to convert your voice commands into planning actions.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>Timed OAuth Callback</string>
      <key>CFBundleURLSchemes</key>
      <array><string>timed</string></array>
    </dict>
    <dict>
      <key>CFBundleURLName</key>
      <string>MSAL Auth</string>
      <key>CFBundleURLSchemes</key>
      <array><string>msauth.com.timed.app</string></array>
    </dict>
    <dict>
      <key>CFBundleURLName</key>
      <string>Google OAuth Callback</string>
      <key>CFBundleURLSchemes</key>
      <array><string>com.googleusercontent.apps.461539145615-8e2sknd45hrs7bnuq6uf1h55hkhfqi8u</string></array>
    </dict>
  </array>
  <key>GIDClientID</key>
  <string>461539145615-8e2sknd45hrs7bnuq6uf1h55hkhfqi8u.apps.googleusercontent.com</string>
</dict>
</plist>
PLIST

codesign_bundle --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/MSAL.framework" 2>/dev/null || true
codesign_bundle --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/Frameworks/LiveKitWebRTC.framework" 2>/dev/null || true
# Apply the canonical macOS entitlements. Ad-hoc builds still cannot use a
# keychain access group; pass TIMED_CODESIGN_IDENTITY with a Developer ID
# Application identity for notarizable release artifacts.
codesign_bundle \
    --entitlements "$ROOT_DIR/Platforms/Mac/Timed.entitlements" \
    --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "Packaged $APP_DIR"
