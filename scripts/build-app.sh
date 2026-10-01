#!/bin/zsh
# Builds VoiceText.app, signs it with the local identity and installs it to ~/Applications.
# Usage: scripts/build-app.sh [--no-install] [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=1
for arg in "$@"; do
  case $arg in
    --no-install) INSTALL=0 ;;
    --debug) CONFIG=debug ;;
  esac
done

APP_NAME=VoiceText
BUNDLE_ID=com.daniel.voicetext
IDENTITY="VoiceText Local Signing"
VERSION=0.1.0
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c "$CONFIG" --product "$APP_NAME" 2>&1 | grep -v "search path" | grep -E "error|warning: |Build complete" || true
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
[[ -x "$BIN_DIR/$APP_NAME" ]] || { echo "Build failed"; exit 1; }

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM resource bundles; Bundle.module looks in Contents/Resources first.
for bundle in "$BIN_DIR"/*.bundle; do
  [[ "$(basename "$bundle")" == *Tests.bundle ]] && continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSMicrophoneUsageDescription</key><string>VoiceText records your voice while you hold the dictation shortcut and transcribes it on this Mac.</string>
</dict>
</plist>
PLIST

cat > build/entitlements.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  SIGN_AS="$IDENTITY"
else
  echo "warning: '$IDENTITY' not found (run scripts/create-signing-cert.sh); ad-hoc signing — permissions will reset on every rebuild"
  SIGN_AS="-"
fi
codesign --force --deep --options runtime --timestamp=none \
  --entitlements build/entitlements.plist --sign "$SIGN_AS" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($CONFIG, build $BUILD_NUMBER)"

if [[ $INSTALL == 1 ]]; then
  DEST="$HOME/Applications/$APP_NAME.app"
  pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "Installed to $DEST"
fi
