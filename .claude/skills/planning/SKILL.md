# /plan — Plan a new Bar Ticket feature

**Invocation:** `/plan [branch-name] [feature-description]`

**Purpose:** Creates a detailed implementation plan for a new Bar Ticket feature, including both app and optional website updates.

## What it does

1. Takes a branch name and feature description as arguments
2. Creates a comprehensive feature plan with architecture and implementation steps
3. If website changes are needed, consults the bar-ticket-site-developer agent
4. Appends a "Bar Ticket Website" section if applicable
5. Saves the plan to `.claude/plans/` as a markdown file
6. Outputs the finished plan to the terminal

## Prerequisites

- Branch name follows Night District conventions: `feat/`, `fix/`, `change/`, `test/`, `design/`
- Feature description clearly states what needs to be built

## Usage

```bash
/plan feat/dark-mode "Add dark mode toggle to app and website"
```

or

```bash
/plan fix/notch-lag "Fix notch animation lag on slower MacBooks"
```

## Plan structure

The generated plan includes:

1. **Overview** — Feature summary and scope
2. **Architecture** — Key components and design decisions
3. **Implementation Steps** — Detailed task breakdown
4. **Bar Ticket Website** (if applicable) — Related website changes
5. **Testing** — How to verify the feature works
6. **Files to change** — Critical files touched

## Plan attributes

Each plan markdown file includes:

```markdown
---
branch: feat/feature-name
description: What this feature does
date: 2026-04-05
---
```

## Example output

```
📋 Plan created: .claude/plans/feat-dark-mode.md

✓ Bar Ticket app implementation
✓ Website changes identified and planned
✓ Ready to start development on feat/dark-mode branch
```
