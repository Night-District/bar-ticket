#!/bin/bash

echo "🧹 Bar Ticket Cleanup Script"
echo "==========================="
echo ""

echo "Deleting Application Support files..."
rm -rf ~/Library/Application\ Support/BarTicket*

echo "Deleting Preferences..."
rm -f ~/Library/Preferences/com.nightdistrict.BarTicket.plist

echo "Deleting Caches..."
rm -rf ~/Library/Caches/BarTicket

echo "Deleting Saved Application State..."
rm -rf ~/Library/Saved\ Application\ State/com.nightdistrict.BarTicket.savedState

echo "Deleting Keychain GitHub token..."
security delete-generic-password -s com.nightdistrict.BarTicket -a github ~/Library/Keychains/login.keychain-db 2>/dev/null || true

echo ""
echo "✅ Cleanup complete. Verifying..."
echo ""

echo "Checking Application Support:"
ls -la ~/Library/Application\ Support/ | grep -i barticket || echo "  ✓ Cleared"

echo "Checking Preferences:"
ls -la ~/Library/Preferences/ | grep -i barticket || echo "  ✓ Cleared"

echo "Checking Caches:"
ls -la ~/Library/Caches/ | grep -i barticket || echo "  ✓ Cleared"

echo "Checking Keychain:"
security find-generic-passwords -s com.nightdistrict.BarTicket ~/Library/Keychains/login.keychain-db 2>&1 | grep -q "SecItemNotFound" && echo "  ✓ Cleared" || echo "  ⚠ Token may still exist"

echo ""
echo "🎉 Bar Ticket is fully uninstalled. Ready for a fresh start!"
