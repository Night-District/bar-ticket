#!/bin/bash
set -e

EXPORT_DIR="$HOME/Developer/night-district/bar-ticket/exports"
SITE_DIR="$HOME/Developer/night-district/bar-ticket-site"

# Find newest .app
APP=$(ls -td "$EXPORT_DIR"/*.app 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "❌ No .app found in $EXPORT_DIR"
  exit 1
fi

APP_NAME=$(basename "$APP")
echo "✓ Found: $APP_NAME"

# Create .dmg
DMG="$SITE_DIR/assets/releases/BarTicket.dmg"
echo "🔨 Creating .dmg..."
hdiutil create -volname "Bar Ticket" -srcfolder "$APP" -ov -format UDZO "$DMG"
DMG_SIZE=$(du -sh "$DMG" | cut -f1)
echo "✓ Created: BarTicket.dmg ($DMG_SIZE)"

# Commit and push
cd "$SITE_DIR"
git add assets/releases/BarTicket.dmg
git commit -m "Update Bar Ticket .dmg

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push
echo "✓ Pushed to main"

# Get live URL
echo ""
echo "🌐 Live at: https://night-district.github.io/bar-ticket-site/"
