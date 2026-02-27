#!/usr/bin/env bash
set -euo pipefail

# Creates a polished DMG installer with a drag-to-Applications layout,
# background image, and positioned icons.
#
# Usage: ./scripts/create-dmg.sh <path-to.app> <output.dmg> [version]
#
# Example: ./scripts/create-dmg.sh build/Speak.app build/Speak.dmg 0.1.0

APP_PATH="${1:?Usage: create-dmg.sh <app-path> <output-dmg> [version]}"
DMG_PATH="${2:?Usage: create-dmg.sh <app-path> <output-dmg> [version]}"
VERSION="${3:-dev}"

APP_NAME="$(basename "$APP_PATH" .app)"
VOLUME_NAME="${APP_NAME} ${VERSION}"
STAGING_DIR="$(mktemp -d)"
TMP_DMG_DIR="$(mktemp -d)"
RW_DMG="$TMP_DMG_DIR/rw.dmg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BG_PNG="$SCRIPT_DIR/dmg-background.png"

cleanup() {
    # Detach if still mounted (ignore errors)
    if [[ -n "${MOUNT_POINT:-}" ]] && mount | grep -q "$MOUNT_POINT"; then
        hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
    fi
    rm -rf "$STAGING_DIR" "$TMP_DMG_DIR"
}
trap cleanup EXIT

# --- 1. Stage contents ---
echo "==> Staging DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/"
# Create a Finder alias (not a symlink) so the Applications folder icon renders.
# Fall back to a symlink in headless/CI environments where Finder is unavailable.
if ! osascript -e "tell application \"Finder\" to make alias file to POSIX file \"/Applications\" at POSIX file \"$STAGING_DIR\""; then
    echo "WARNING: Could not create Finder alias; falling back to symlink." >&2
    ln -s /Applications "$STAGING_DIR/Applications"
fi

# Hidden .background folder for the background image
mkdir -p "$STAGING_DIR/.background"
cp "$BG_PNG" "$STAGING_DIR/.background/background.png"

# --- 3. Create read-write DMG ---
echo "==> Creating read-write DMG..."
# Size the DMG with headroom for .DS_Store and background
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "$RW_DMG"

# --- 4. Mount read-write DMG ---
echo "==> Mounting DMG..."
MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | grep '^/dev/' | tail -1 | awk -F'\t' '{print $NF}' | sed 's/^ *//')"

echo "   Mounted at: $MOUNT_POINT"

# --- 5. Apply Finder view settings via AppleScript ---
echo "==> Configuring Finder appearance..."

apply_appearance() {
    osascript <<APPLESCRIPT
        tell application "Finder"
            tell disk "$VOLUME_NAME"
                open
                delay 2

                set cw to container window
                set current view of cw to icon view
                set toolbar visible of cw to false
                set statusbar visible of cw to false
                set the bounds of cw to {100, 100, 760, 500}

                set viewOptions to the icon view options of cw
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 128
                set background picture of viewOptions to file ".background:background.png"

                set position of item "${APP_NAME}.app" of cw to {160, 200}
                set position of item "Applications" of cw to {500, 200}

                -- close and reopen to force Finder to persist .DS_Store
                close
                open
                delay 2
                set cw to container window
                set toolbar visible of cw to false
                set statusbar visible of cw to false
                set the bounds of cw to {100, 100, 760, 500}
                close
            end tell
        end tell
APPLESCRIPT
}

# Retry up to 3 times — AppleScript Finder automation can be flaky in CI
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "   Attempt $attempt/$MAX_RETRIES..."
    if apply_appearance; then
        echo "   AppleScript succeeded."
        break
    fi
    if [[ $attempt -eq $MAX_RETRIES ]]; then
        echo "WARNING: AppleScript failed after $MAX_RETRIES attempts. DMG will work but may lack visual styling." >&2
        break
    fi
    sleep 2
done

# Verify .DS_Store was created (indicates Finder settings were saved)
if [[ -f "$MOUNT_POINT/.DS_Store" ]]; then
    echo "   .DS_Store confirmed."
else
    echo "   WARNING: .DS_Store not found — Finder settings may not have persisted." >&2
fi

# --- 6. Finalise ---
echo "==> Detaching DMG..."
sync
DETACH_OK=0
for attempt in 1 2 3; do
    if hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
        DETACH_OK=1
        break
    fi
    sleep 1
done
if [[ $DETACH_OK -ne 1 ]]; then
    hdiutil detach "$MOUNT_POINT" -force
fi
unset MOUNT_POINT

echo "==> Converting to compressed read-only DMG..."
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

echo "==> Done: $DMG_PATH"
