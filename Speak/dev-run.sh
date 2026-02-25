#!/bin/bash
# Build a debug binary and wrap it in a minimal .app bundle so that
# Bundle.main.bundleIdentifier, permission descriptions, and Sparkle
# all work correctly during development.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c debug

BUILD_DIR=".build/debug"
APP_DIR="$BUILD_DIR/Speak Dev.app/Contents"
mkdir -p "$APP_DIR/MacOS"
cp "$BUILD_DIR/Speak" "$APP_DIR/MacOS/Speak"
cp Speak/Info.plist "$APP_DIR/Info.plist"

# Override bundle ID and display name so dev builds get independent TCC permissions
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.speak.app.dev" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Speak Dev" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Speak Dev" "$APP_DIR/Info.plist"

# Symlink Sparkle.framework so @loader_path resolution works
SPARKLE_FW="$BUILD_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
    echo "error: Sparkle.framework not found at $SPARKLE_FW" >&2
    exit 1
fi
ln -sfh "../../../Sparkle.framework" "$APP_DIR/MacOS/Sparkle.framework"

# Copy the bundled resources SPM generates (Assets.xcassets, etc.)
BUNDLE_RESOURCE="$BUILD_DIR/Speak_Speak.bundle"
if [ -d "$BUNDLE_RESOURCE" ]; then
    mkdir -p "$APP_DIR/Resources"
    cp -R "$BUNDLE_RESOURCE" "$APP_DIR/Resources/"
fi

# Re-codesign the .app bundle so macOS TCC recognises it for permission prompts.
# The cp above invalidates the original SPM ad-hoc signature. The designated
# requirement pins TCC permissions to the bundle ID so they persist across rebuilds.
codesign --force --sign - --deep \
    --entitlements Speak/Speak.entitlements \
    -r="designated => identifier \"com.speak.app.dev\"" \
    "$BUILD_DIR/Speak Dev.app"

# Kill any running Speak instances (dev and prod conflict at runtime over hotkeys,
# microphone, etc.)
APP_PATH="$(cd "$BUILD_DIR" && pwd)/Speak Dev.app"
pkill -xf ".*/Speak\.app/Contents/MacOS/Speak" 2>/dev/null || true
pkill -f "$APP_PATH/Contents/MacOS/Speak" 2>/dev/null || true
sleep 0.5

# Launch via `open -n` with absolute path. -n forces a new instance so Launch
# Services won't redirect to /Applications/Speak.app. Using `open` (not exec)
# is required so macOS sets up the full .app bundle context — TCC reads
# Info.plist usage descriptions from the bundle, not the bare binary.
echo "Launching $APP_PATH ..."
open -n "$APP_PATH"
