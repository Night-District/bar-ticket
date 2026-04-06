#!/bin/bash
set -e

# Parse arguments
BRANCH="${1}"
DESCRIPTION="${2}"

if [ -z "$BRANCH" ] || [ -z "$DESCRIPTION" ]; then
  echo "❌ Usage: /plan [branch-name] [feature-description]"
  echo ""
  echo "Examples:"
  echo "  /plan feat/dark-mode 'Add dark mode toggle'"
  echo "  /plan fix/notch-lag 'Fix animation lag'"
  exit 1
fi

# Validate branch name format
if ! [[ "$BRANCH" =~ ^(feat|fix|change|test|design)/ ]]; then
  echo "❌ Branch must start with: feat/, fix/, change/, test/, or design/"
  exit 1
fi

# Create plans directory if it doesn't exist
mkdir -p .claude/plans

# Generate filename from branch name
PLAN_FILE=".claude/plans/${BRANCH//\//-}.md"
TODAY=$(date +%Y-%m-%d)

# Check if plan already exists
if [ -f "$PLAN_FILE" ]; then
  echo "⚠️  Plan already exists: $PLAN_FILE"
  echo "Delete it first if you want to regenerate."
  exit 1
fi

# Create the plan with frontmatter
cat > "$PLAN_FILE" << 'EOF'
---
branch: BRANCH_PLACEHOLDER
description: DESCRIPTION_PLACEHOLDER
date: DATE_PLACEHOLDER
---

# Feature Plan: DESCRIPTION_PLACEHOLDER

## Overview

DESCRIPTION_PLACEHOLDER

### Scope
- App implementation
- Testing
- Deployment

## Architecture

### Key Components
- Identify which existing components will be modified
- New components if needed
- Integration points

### Design Decisions
- Why this approach?
- Alternatives considered
- Trade-offs

## Implementation Steps

### Phase 1: Core Implementation
1. Identify files to modify
2. Implement core logic
3. Update views if needed
4. Test changes

### Phase 2: Integration
1. Connect to existing systems
2. Verify state management
3. Handle edge cases

### Phase 3: Polish
1. Add animations/transitions
2. Error handling
3. Performance optimization

## Testing

- [ ] Unit tests pass
- [ ] Manual testing on M-series Mac
- [ ] Manual testing on Intel Mac
- [ ] Notch behavior verified
- [ ] No regressions

## Files to Change

- `BarTicket/BarTicketApp.swift` — Entry point
- `BarTicket/ViewModels/AppState.swift` — State management
- `BarTicket/Views/*.swift` — UI components
- `BarTicket/Services/*.swift` — Business logic

## Notes

Add implementation notes and gotchas here as you discover them.

EOF

# Replace placeholders (using | as delimiter to avoid issues with / in branch names)
sed -i '' "s|BRANCH_PLACEHOLDER|$BRANCH|g" "$PLAN_FILE"
sed -i '' "s|DESCRIPTION_PLACEHOLDER|$DESCRIPTION|g" "$PLAN_FILE"
sed -i '' "s|DATE_PLACEHOLDER|$TODAY|g" "$PLAN_FILE"

echo "✓ Plan created: $PLAN_FILE"
echo ""
cat "$PLAN_FILE"
