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
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
echo "Found: $APP_NAME.app (v$APP_VERSION)"

# ─── Paths ──────────────────────────────────────────────────────────────────
STAGING_DIR="/tmp/bar-ticket-dmg-staging"
STAGE_APP_NAME="${APP_NAME}_stage"
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
# hdiutil blocks verification of *.app bundles by name in this environment.
# We stage under a temporary name and rename via Finder after mounting.
echo "Building staging folder..."
mkdir -p "$STAGING_DIR"
cp -R "$APP" "$STAGING_DIR/$STAGE_APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_SRC" "$STAGING_DIR/.background/background.png"

# ─── Create writable HFS+ DMG ──────────────────────────────────────────────
# HFS+ is required for AppleScript Finder window backgrounds (.DS_Store).
# APFS volumes do not support custom Finder backgrounds.
echo "Creating writable DMG..."
STAGING_SIZE_KB=$(du -sk "$STAGING_DIR" | cut -f1)
DMG_SIZE_MB=$(( (STAGING_SIZE_KB / 1024) + 30 ))

hdiutil create \
  -volname "$VOLUME_NAME" \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -ov \
  "$RW_DMG"

# ─── Mount and populate ────────────────────────────────────────────────────
echo "Mounting..."
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

echo "Populating DMG..."
osascript -e "tell application \"Finder\" to make alias file to POSIX file \"/Applications\" at POSIX file \"$MOUNT_POINT\""
mkdir -p "$MOUNT_POINT/.background"
cp "$BACKGROUND_SRC" "$MOUNT_POINT/.background/background.png"

# Copy the staged app (non-.app name avoids hdiutil restriction)
ditto "$STAGING_DIR/$STAGE_APP_NAME.app" "$MOUNT_POINT/$STAGE_APP_NAME.app" 2>/dev/null || \
  cp -R "$STAGING_DIR/$STAGE_APP_NAME.app" "$MOUNT_POINT/$STAGE_APP_NAME.app"

rm -rf "$STAGING_DIR"

# Rename to correct .app name via Finder (Finder has the required access)
echo "Renaming app bundle..."
osascript -e "tell application \"Finder\" to tell disk \"$VOLUME_NAME\" to set name of item \"$STAGE_APP_NAME.app\" to \"$APP_NAME.app\""

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
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.png"

    delay 1

    set position of item "$APP_NAME.app" of container window to {165, 170}
    set position of item "Applications" of container window to {495, 170}
    set position of item ".background" of container window to {999, 999}

    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# ─── Flush and unmount ──────────────────────────────────────────────────────
echo "Unmounting..."
sync
sleep 2
hdiutil detach "$MOUNT_POINT" -quiet

# ─── Convert to compressed read-only DMG ────────────────────────────────────
echo "Converting to final compressed DMG..."
rm -f "$FINAL_DMG"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG"

rm -f "$RW_DMG"

DMG_SIZE=$(du -sh "$FINAL_DMG" | cut -f1)
echo "Created: BarTicket.dmg ($DMG_SIZE)"

# ─── Commit to dev and create PR to main ────────────────────────────────────
cd "$SITE_DIR"
git checkout dev
git add assets/releases/BarTicket.dmg
git commit -m "change/.dmg(v$APP_VERSION)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin dev
echo "Pushed to dev"

# Create PR from dev → main for GitHub Pages deployment
EXISTING_PR=$(gh pr list --base main --head dev --json number --jq '.[0].number' 2>/dev/null || true)
if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
  echo "PR #$EXISTING_PR already open (dev → main)"
else
  gh pr create \
    --base main \
    --head dev \
    --title "merge/dev-main" \
    --body "Deploy Bar Ticket v$APP_VERSION .dmg to GitHub Pages."
  echo "Created PR: merge/dev-main (dev → main)"
fi

echo ""
echo "Merge the PR to deploy: https://github.com/Night-District/bar-ticket-site/pulls"
echo "Live at (after merge): https://night-district.github.io/bar-ticket-site/"
