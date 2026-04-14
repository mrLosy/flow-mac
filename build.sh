#!/bin/bash

# Build script for Flow Mac
# Builds via SPM and packages into a macOS .app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="FlowMac"
BUNDLE_ID="com.flowmac.app"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_MACOS="13.0"

BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Building $APP_NAME..."

# 1. Build with SPM
swift build -c release 2>&1 | grep -v "warning:"
BINARY="$SCRIPT_DIR/.build/release/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "Build failed: binary not found"
    exit 1
fi

# 2. Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 3. Copy binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"

# 4. Create Info.plist with resolved variables
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Flow Mac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2024 Flow Mac. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Flow Mac needs access to your microphone to capture voice for transcription.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Flow Mac needs accessibility access to insert transcribed text into other applications.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# 5. Sign the app with stable identifier to preserve permissions across rebuilds
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install: cp -R $APP_BUNDLE /Applications/"
