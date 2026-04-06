# /plan — Plan a new Bar Ticket feature

**Invocation:** `/plan [branch-name] [feature-description]`

**Purpose:** Interactive planning session that asks clarifying questions about your feature and produces a detailed implementation plan.

## What it does

1. Takes a branch name and initial feature description
2. **Asks clarifying questions** about:
   - Feature scope and impact area (app, website, or both)
   - Technical approach and design pattern
   - User-facing changes vs. internal improvements
   - Performance or complexity concerns
   - Dependencies or integration points
3. Presents multiple choice answers or allows custom input
4. Uses your answers to design the technical solution
5. If website changes are needed, consults the `bar-ticket-site-developer` agent
6. Generates a comprehensive plan and saves to `.claude/plans/`

## Prerequisites

- Branch name follows Night District conventions: `feat/`, `fix/`, `change/`, `test/`, `design/`
- Have a rough idea of what you want to build (details refined during Q&A)

## Usage

```bash
/plan feat/dark-mode "Add dark mode support"
```

Claude will then ask:

> **Where should dark mode be implemented?**
> - [ ] App UI only
> - [ ] Website only
> - [ ] Both app and website
> - [ ] Other: _____

> **What triggers dark mode?**
> - [ ] System preference (macOS dark mode)
> - [ ] Manual toggle in settings
> - [ ] Both
> - [ ] Other: _____

> **Should dark mode persist across restarts?**
> - [ ] Yes, save preference
> - [ ] Always follow system
> - [ ] Other: _____

## Interactive question types

Questions present:
- **Single select** — Pick one option
- **Multiple select** — Pick one or more options
- **Custom text** — Always has "Other: ___" option for custom answers
- **Yes/No** — Quick decisions
- **Numeric** — Performance budgets, timeouts, etc.

See `.claude/skills/planning/questions.md` for the full list of questions Claude will ask.

## Plan output

The generated plan includes:

1. **Overview** — Feature summary derived from your answers
2. **Scope** — What's included and what's not
3. **Architecture** — Technical design based on your choices
4. **Implementation Steps** — Phased breakdown with clear milestones
5. **Bar Ticket Website** — If applicable, specific website changes
6. **Testing** — Verification strategy for your feature
7. **Files to change** — Exact files you'll modify
8. **Decisions log** — Why specific choices were made

## Plan attributes

Each plan markdown file includes:

```markdown
---
branch: feat/feature-name
description: What this feature does
date: 2026-04-05
scope: app | website | both
technical_approach: [key decisions]
---
```

## Example workflow

```
/plan feat/dynamic-island-animation "Improve notch animation performance"

❓ "Where is the performance issue?"
→ ☑️ Notch state transitions are janky

❓ "What's the target frame rate?"
→ 60 FPS (selected)

❓ "Should we cache icon states?"
→ Yes, custom cache strategy per icon type

📋 Plan created: .claude/plans/feat-dynamic-island-animation.md

✓ Problem identified: State transition lag
✓ Solution: Implement predictive caching with debouncing
✓ Ready to develop on feat/dynamic-island-animation
```
