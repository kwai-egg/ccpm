#!/bin/bash
# Initialize coordination directory for an epic/issue
EPIC_NAME=$1

if [ -z "$EPIC_NAME" ]; then
    echo "Usage: coordination-init.sh <epic-name>"
    exit 1
fi

mkdir -p .claude/epics/$EPIC_NAME/coordination
echo "initialized: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > .claude/epics/$EPIC_NAME/coordination/execution-log.md

echo "Coordination directory initialized for epic: $EPIC_NAME"