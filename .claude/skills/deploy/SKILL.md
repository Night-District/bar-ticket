# /deploy — Deploy new Bar Ticket .dmg to website

**Invocation:** `/deploy`

**Purpose:** Automates the distribution pipeline after you've exported a notarized `.app` from Xcode.

## What it does

1. Finds the newest `.app` in `/Users/loganriedley/Developer/night-district/bar-ticket/exports/`
2. Creates a signed `.dmg` from it using `hdiutil create`
3. Replaces `bar-ticket-site/assets/releases/BarTicket.dmg`
4. Commits and pushes to the site repo (triggers GitHub Pages deployment)

## Prerequisites

- You have already:
  - Archived the app in Xcode
  - Distributed as Developer ID (notarization completed)
  - Exported the notarized `.app` to `bar-ticket/exports/`

## Usage

```
/deploy
```

The skill will:
- Find the latest `.app` file
- Confirm the file and version
- Create the `.dmg`
- Push to GitHub (workflow deploys automatically)
- Return the live URL

## Example output

```
✓ Found: BarTicket.app (modified 2 minutes ago)
✓ Created: BarTicket.dmg (1.9 MB)
✓ Pushed to main
🌐 Live at: https://night-district.github.io/bar-ticket-site/
```

## Files involved

- **Input**: `~/Developer/night-district/bar-ticket/exports/*.app`
- **Output**: `~/Developer/night-district/bar-ticket-site/assets/releases/BarTicket.dmg`
- **Repo**: `Night-District/bar-ticket-site` on GitHub
