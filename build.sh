#!/bin/bash

# Build script for Flow Mac
# This script builds the Flow Mac app using Swift Package Manager

set -e

echo "🔨 Building Flow Mac..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Error: This script must be run on macOS"
    exit 1
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift is not installed"
    exit 1
fi

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode is not installed"
    exit 1
fi

# Build with Swift Package Manager
echo "📦 Building with Swift Package Manager..."
swift build -c release

# Or build with Xcode
echo "🔨 Building with Xcode..."
xcodebuild -project FlowMac.xcodeproj \
    -scheme FlowMac \
    -configuration Release \
    -derivedDataPath build \
    clean build

echo "✅ Build complete!"
echo ""
echo "App location: build/Build/Products/Release/FlowMac.app"
