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

# Create initial plan with frontmatter
cat > "$PLAN_FILE" << EOF
---
branch: $BRANCH
description: $DESCRIPTION
date: $TODAY
scope:
technical_approach:
---

# Feature Plan: $DESCRIPTION

## Overview

$DESCRIPTION

## Scope

(To be determined during planning session)

## Architecture

(To be determined during planning session)

## Implementation Steps

(To be determined during planning session)

## Testing

(To be determined during planning session)

## Files to Change

(To be determined during planning session)

## Notes

(Planning in progress...)

EOF

echo "✓ Planning session initiated: $PLAN_FILE"
echo ""
echo "🤔 Claude will now ask clarifying questions to design the best solution."
echo "   Answer with single/multiple selections or provide custom input."
