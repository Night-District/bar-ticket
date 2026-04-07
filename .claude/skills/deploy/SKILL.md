# /deploy — Deploy new Bar Ticket .dmg to website

**Invocation:** `/deploy`

**Purpose:** Automates the distribution pipeline after you've exported a notarized `.app` from Xcode.

## What it does

1. Finds the newest `.app` in `/Users/loganriedley/Developer/night-district/bar-ticket/exports/`
2. Creates a writable HFS+ DMG, populates it with the `.app`, an `/Applications` symlink, and the branded background image
3. Configures the Finder window layout via AppleScript (background image, icon positions, window size)
4. Converts the configured DMG to a compressed read-only `.dmg`
5. Commits the `.dmg` to the `dev` branch of `bar-ticket-site`
6. Creates a PR from `dev` → `main` titled `merge/dev-main` (or reports if one already exists)
7. After the PR is merged, GitHub Pages deploys automatically from `main`

## Prerequisites

- You have already:
  - Archived the app in Xcode
  - Distributed as Developer ID (notarization completed)
  - Exported the notarized `.app` to `bar-ticket/exports/`
- `gh` CLI is authenticated (for PR creation)

## Usage

```
/deploy
```

The skill will:
- Find the latest `.app` file and display its version
- Create the branded drag-to-install `.dmg`
- Push to `dev` and create a PR to `main`
- Return the PR URL for you to merge

## Example output

```
Found: BarTicket.app (v1.1)
Created: BarTicket.dmg (1.8 MB)
Pushed to dev
Created PR: merge/dev-main (dev → main)

Merge the PR to deploy: https://github.com/Night-District/bar-ticket-site/pulls
Live at (after merge): https://night-district.github.io/bar-ticket-site/
```

## Files involved

- **Input**: `~/Developer/night-district/bar-ticket/exports/*.app`
- **Output**: `~/Developer/night-district/bar-ticket-site/assets/releases/BarTicket.dmg`
- **Repo**: `Night-District/bar-ticket-site` on GitHub
- **Deploy trigger**: Push to `main` branch → GitHub Pages workflow

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

## Technical notes

- **HFS+ required**: The writable DMG uses HFS+ (not APFS) because AppleScript-set Finder window backgrounds only persist on HFS+ volumes via `.DS_Store`.
- **Staged app naming**: `hdiutil` blocks verification of `.app` bundles by name in the Claude Code environment. The app is staged under a `_stage.app` name and renamed to the correct name via Finder (which has the required access) after mounting.
