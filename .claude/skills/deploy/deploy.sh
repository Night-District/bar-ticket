#!/bin/bash
set -e

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="$HOME/Developer/night-district/bar-ticket/exports"
SITE_DIR="$HOME/Developer/night-district/bar-ticket-site"
BACKGROUND_SRC="$DEPLOY_DIR/dmg-background.png"

# ─── Find newest .app ───────────────────────────────────────────────────────
APP=$(ls -td "$EXPORT_DIR"/*.app 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "No .app found in $EXPORT_DIR"
  exit 1
fi

APP_NAME=$(basename "$APP" .app)
echo "Found: $APP_NAME.app"

# ─── Paths ──────────────────────────────────────────────────────────────────
STAGING_DIR="/tmp/bar-ticket-dmg-staging"
RW_DMG="/tmp/BarTicket-rw.dmg"
FINAL_DMG="$SITE_DIR/assets/releases/BarTicket.dmg"
VOLUME_NAME="Bar Ticket"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# ─── Clean up from any previous failed run ──────────────────────────────────
rm -rf "$STAGING_DIR"
rm -f "$RW_DMG"

if [ -d "$MOUNT_POINT" ]; then
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
fi

# ─── Build staging folder ───────────────────────────────────────────────────
echo "Building staging folder..."
mkdir -p "$STAGING_DIR/.background"

cp -R "$APP" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [ ! -f "$BACKGROUND_SRC" ]; then
  echo "Background image not found at $BACKGROUND_SRC"
  echo "Run: python3 $DEPLOY_DIR/generate-background.py"
  exit 1
fi
cp "$BACKGROUND_SRC" "$STAGING_DIR/.background/background.png"

# ─── Create writable DMG from staging folder ────────────────────────────────
echo "Creating writable DMG..."
STAGING_SIZE_KB=$(du -sk "$STAGING_DIR" | cut -f1)
DMG_SIZE_MB=$(( (STAGING_SIZE_KB / 1024) + 20 ))

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "$RW_DMG"

# ─── Mount the writable DMG ─────────────────────────────────────────────────
echo "Mounting writable DMG..."
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

sleep 2

# ─── Configure Finder window via AppleScript ────────────────────────────────
echo "Configuring Finder window layout..."
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open

    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 1060, 600}

    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"

    set position of item "$APP_NAME.app" of container window to {165, 175}
    set position of item "Applications" of container window to {495, 175}

    close
    open

    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# ─── Flush and unmount ──────────────────────────────────────────────────────
echo "Unmounting..."
sync
hdiutil detach "$MOUNT_POINT" -quiet

# ─── Convert to compressed read-only DMG ────────────────────────────────────
echo "Converting to compressed DMG..."
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG"

# ─── Clean up temp files ────────────────────────────────────────────────────
rm -rf "$STAGING_DIR"
rm -f "$RW_DMG"

DMG_SIZE=$(du -sh "$FINAL_DMG" | cut -f1)
echo "Created: BarTicket.dmg ($DMG_SIZE)"

# ─── Commit and push ────────────────────────────────────────────────────────
cd "$SITE_DIR"
git add assets/releases/BarTicket.dmg
git commit -m "Update Bar Ticket .dmg

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
echo "Pushed to main"

echo ""
echo "Live at: https://night-district.github.io/bar-ticket-site/"
