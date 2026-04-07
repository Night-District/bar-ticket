# /deploy — Deploy new Bar Ticket .dmg to website

**Invocation:** `/deploy`

**Purpose:** Automates the distribution pipeline after you've exported a notarized `.app` from Xcode.

## What it does

1. Finds the newest `.app` in `/Users/loganriedley/Developer/night-district/bar-ticket/exports/`
2. Builds a staging folder with the `.app`, an `/Applications` symlink, and the branded background image
3. Creates a writable HFS+ DMG, mounts it, and configures the Finder window layout via AppleScript (background image, icon positions, window size)
4. Converts the configured DMG to a compressed read-only `.dmg`
5. Replaces `bar-ticket-site/assets/releases/BarTicket.dmg`
6. Commits and pushes to the site repo (triggers GitHub Pages deployment)

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

## DMG background image

The installer window uses a Night District branded background image:

- **Asset**: `.claude/skills/deploy/dmg-background.png` (660x400 px, committed to repo)
- **Generator**: `.claude/skills/deploy/generate-background.py` (Pillow-based, also committed)

The PNG is pre-committed so deploy does not require Python at runtime. To regenerate after a design change:

```bash
python3 -m venv /tmp/bt-venv
/tmp/bt-venv/bin/pip install Pillow
/tmp/bt-venv/bin/python3 .claude/skills/deploy/generate-background.py
# Review the output, then commit dmg-background.png
```
