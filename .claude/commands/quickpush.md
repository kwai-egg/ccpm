#!/bin/bash

# Get the output of the last command from history
LAST_CMD_OUTPUT=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')
if [ -z "$LAST_CMD_OUTPUT" ]; then
    LAST_CMD_OUTPUT="Quick commit"
fi

# Create a TLDR commit message (first 72 chars)
COMMIT_MSG=$(echo "$LAST_CMD_OUTPUT" | cut -c1-72)

# Add all changes, commit, and push to current branch
git add -A
git commit -m "$COMMIT_MSG"
git push origin $(git branch --show-current)

echo "Pushed with message: $COMMIT_MSG"