#!/bin/bash
# Build a debug binary and wrap it in a minimal .app bundle so that
# Bundle.main.bundleIdentifier, permission descriptions, and Sparkle
# all work correctly during development.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c debug

BUILD_DIR=".build/debug"
APP_DIR="$BUILD_DIR/Speak.app/Contents"
mkdir -p "$APP_DIR/MacOS"
cp "$BUILD_DIR/Speak" "$APP_DIR/MacOS/Speak"
cp Speak/Info.plist "$APP_DIR/Info.plist"

# Symlink Sparkle.framework so @loader_path resolution works
ln -sfh "../../../Sparkle.framework" "$APP_DIR/MacOS/Sparkle.framework"

# Copy the bundled resources SPM generates (Assets.xcassets, etc.)
BUNDLE_RESOURCE="$BUILD_DIR/Speak_Speak.bundle"
if [ -d "$BUNDLE_RESOURCE" ]; then
    mkdir -p "$APP_DIR/Resources"
    cp -R "$BUNDLE_RESOURCE" "$APP_DIR/Resources/"
fi

# Re-codesign the .app bundle so macOS TCC recognises it for permission prompts.
# The cp above invalidates the original SPM ad-hoc signature.
codesign --force --sign - --deep "$BUILD_DIR/Speak.app"

# Kill any existing instance
pkill -f "Speak.app/Contents/MacOS/Speak" 2>/dev/null || true
sleep 0.5

# Launch via `open -n` with absolute path. -n forces a new instance so Launch
# Services won't redirect to /Applications/Speak.app. Using `open` (not exec)
# is required so macOS sets up the full .app bundle context — TCC reads
# Info.plist usage descriptions from the bundle, not the bare binary.
APP_PATH="$(cd "$BUILD_DIR" && pwd)/Speak.app"
echo "Launching $APP_PATH ..."
open -n "$APP_PATH"
