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
SPARKLE_FW="$BUILD_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
    echo "error: Sparkle.framework not found at $SPARKLE_FW" >&2
    exit 1
fi
ln -sfh "../../../Sparkle.framework" "$APP_DIR/MacOS/Sparkle.framework"

# SPM doesn't compile .xcassets into Assets.car — do it manually with actool,
# in-place in the SPM resource bundle. The generated Bundle.module accessor
# falls back to this path when the .app-relative lookup fails.
BUNDLE_RESOURCE="$BUILD_DIR/Speak_Speak.bundle"
XCASSETS="$BUNDLE_RESOURCE/Assets.xcassets"
if [ -d "$XCASSETS" ]; then
    xcrun actool "$XCASSETS" \
        --compile "$BUNDLE_RESOURCE" \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --output-partial-info-plist /dev/null 2>/dev/null
    rm -rf "$XCASSETS"
fi

# Re-codesign the .app bundle so macOS TCC recognises it for permission prompts.
# The cp above invalidates the original SPM ad-hoc signature.
# Include entitlements so the microphone and other capabilities work.
codesign --force --sign - --deep \
    --entitlements Speak/Speak.entitlements \
    "$BUILD_DIR/Speak.app"

# Kill any running Speak instances (both from this build path and other locations)
APP_PATH="$(cd "$BUILD_DIR" && pwd)/Speak.app"
pkill -x "Speak" 2>/dev/null || true
sleep 0.5

# Launch via `open -n` with absolute path. -n forces a new instance so Launch
# Services won't redirect to /Applications/Speak.app. Using `open` (not exec)
# is required so macOS sets up the full .app bundle context — TCC reads
# Info.plist usage descriptions from the bundle, not the bare binary.
echo "Launching $APP_PATH ..."
open -n "$APP_PATH"
