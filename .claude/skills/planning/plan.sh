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

# Check if plan already exists
if [ -f "$PLAN_FILE" ]; then
  echo "⚠️  Plan already exists: $PLAN_FILE"
  echo "Delete it first if you want to regenerate."
  exit 1
fi

echo "🚀 Starting feature planning session for: $BRANCH"
echo ""
echo "📋 Branch: $BRANCH"
echo "📝 Feature: $DESCRIPTION"
echo ""
echo "🤔 Spawning bar-ticket-feature-planner agent..."
echo "   The agent will ask clarifying questions to design the best technical solution."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
