# CLAUDE.md — Bar Ticket

This file provides guidance to Claude Code (claude.ai/code) when working with Bar Ticket.

## Overview

**Bar Ticket** is a macOS menu bar app that automatically creates GitHub issues from TODO comments. When you type a TODO in any editor, save the file, and Bar Ticket detects it, creates the issue, and confirms via a Dynamic Island notch.

**Working directory:** `/Users/loganriedley/Developer/night-district/bar-ticket/`

## Key Architecture

- **Language:** Swift (SwiftUI + AppKit)
- **Platforms:** macOS 14.0+
- **Key Dependencies:**
  - `Alamofire` — networking for GitHub API
  - `DynamicNotchKit` — macOS notch integration
  - `SwiftData` — local persistence (watched dirs, settings, seen TODOs)
- **Project config:** `xcodegen` from `project.yml`

## Directory Structure

```
bar-ticket/
├── BarTicket/              # Main app source
│   ├── BarTicketApp.swift  # App entry + AppDelegate
│   ├── Services/           # FileWatcher, TodoParser, GitResolver, GitHubClient, KeychainService
│   ├── ViewModels/         # AppState.swift
│   ├── Views/              # SettingsView, DynamicIslandWindow (notch UI)
│   ├── Models/             # SwiftData models (AppSettings, WatchedDirectory, SeenTodo)
│   ├── Info.plist
│   ├── BarTicket.entitlements
│   └── Resources/
├── project.yml             # xcodegen config
├── .claude/
│   └── skills/deploy/      # /deploy skill for publishing .dmg
└── exports/                # Where you export notarized .app files
```

## Git Workflow

Bar Ticket follows the **Night District Git Workflow**. Refer to `night-district/hub/git_workflow.md` for the full process.

### Quick summary:

1. **Branch naming:** `feat/`, `fix/`, `change/`, `test/`, `design/` (camelCase description)
2. **Commit message format:** Semicolon-separated imperative statements
   - Example: `add gear icon to detecting state; rotate continuously`
3. **Push to remote immediately** after creating branch
4. **Create PR early** with the same name as your branch
5. **Squash and merge** into `dev` when approved by manager
6. **Delete branch** after merge

### Example workflow:

```bash
git pull
git checkout -b fix/notch-constantly-visible
# make changes
git add BarTicket/Views/DynamicIslandWindow.swift
git commit -m 'disable keepVisible hover behavior; allow notch to dismiss on non-notch macs'
git push -u origin fix/notch-constantly-visible
# create PR in GitHub
```

## Release & Deployment

### Building & signing:

1. **Product > Archive** in Xcode
2. **Distribute App > Direct Distribution** (auto-notarizes)
3. **Export** the notarized `.app` to `bar-ticket/exports/`

### Publishing to website:

```bash
/deploy
```

This runs the `/deploy` skill (`.claude/skills/deploy/deploy.sh`):
- Finds newest `.app` in `exports/`
- Creates `.dmg` via `hdiutil create`
- Commits to `bar-ticket-site` repo
- GitHub Pages deploys automatically
- Live at: https://night-district.github.io/bar-ticket-site/

## Important Code Patterns

### FileWatcher + TODO Detection

- **FileWatcher** watches enabled directories recursively via FSEvents
- **TodoParser** detects `// TODO:` comments (regex match at start of comment body only)
- Content hashing deduplicates TODOs
- `handleNewTodo` pipeline: detecting → creating → confirmed (with min display times)

### Dynamic Island UI

- **DynamicNotchKit** for `.notch` style (black capsule at top center)
- **NotchViewModel** (@Observable) holds icon, title, subtitle, issueURL
- **AnimatedIcon** with `.rotating` (gear/arrow) and `.pulsing` (checkmark) animations
- **hoverBehavior: [.hapticFeedback]** — allows notch to dismiss even on non-notch Macs

### GitHub Integration

- **GitResolver** finds `.git` root, runs `git remote get-url origin`, parses owner/repo
- **GitHubClient** (Alamofire) POSTs issues via GitHub REST API
- **appendIssueReference** writes `(#N url)` back to source file after creation
- **KeychainService** stores GitHub token securely

## Testing & Debugging

- Print statements at every pipeline stage: FileWatcher → TODO parsing → GitHub API → island state
- Watch for false TODO detection in code (e.g., backtick-quoted strings)
- Verify content caching prevents re-triggering on own edits
- Test on both MacBooks (with notch) and external displays (no notch)

## Known Issues & Fixes

- **Notch constantly visible on non-notch Macs:** Disable `.keepVisible` in `hoverBehavior` (fixed)
- **Rapid state transitions:** Ensure minimum display durations (1s detecting, 1s creating, 3s confirmed)
- **False TODO detection in code:** Only match `TODO:` at start of comment body after prefix stripping

## External References

- **Night District Git Workflow:** `night-district/hub/git_workflow.md`
- **Night District Branding:** `night-district/night-district-core/` (colors, fonts, glassmorphism)
- **DynamicNotchKit Docs:** `MrKai77/DynamicNotchKit` on GitHub
