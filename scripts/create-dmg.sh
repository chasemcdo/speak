#!/usr/bin/env bash
set -euo pipefail

# Creates a DMG installer with a drag-to-Applications layout.
#
# Usage: ./scripts/create-dmg.sh <path-to.app> <output.dmg> [version]
#
# Example: ./scripts/create-dmg.sh build/Speak.app build/Speak.dmg 0.1.0

APP_PATH="${1:?Usage: create-dmg.sh <app-path> <output-dmg> [version]}"
DMG_PATH="${2:?Usage: create-dmg.sh <app-path> <output-dmg> [version]}"
VERSION="${3:-dev}"

APP_NAME="$(basename "$APP_PATH" .app)"
STAGING_DIR="$(mktemp -d)"
VOLUME_NAME="${APP_NAME} ${VERSION}"

cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

echo "==> Preparing DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Done: $DMG_PATH"
