#!/bin/bash
# Create a guidance template file for a blocked stream

EPIC_NAME=$1
STREAM_ID=$2

if [ -z "$EPIC_NAME" ] || [ -z "$STREAM_ID" ]; then
    echo "Usage: create-guidance-template.sh <epic-name> <stream-id>"
    exit 1
fi

COORDINATION_DIR=".claude/epics/$EPIC_NAME/coordination"
BLOCKED_FILE="$COORDINATION_DIR/stream-$STREAM_ID-blocked.md"
GUIDANCE_FILE="$COORDINATION_DIR/stream-$STREAM_ID-guidance.md"

if [ ! -f "$BLOCKED_FILE" ]; then
    echo "Error: Stream $STREAM_ID is not marked as blocked for epic $EPIC_NAME"
    echo "Expected file: $BLOCKED_FILE"
    exit 1
fi

if [ -f "$GUIDANCE_FILE" ]; then
    echo "Warning: Guidance file already exists: $GUIDANCE_FILE"
    echo "Edit the existing file or remove it first."
    exit 1
fi

# Extract context from blocked file
REASON=$(grep "^reason:" "$BLOCKED_FILE" | cut -d' ' -f2-)
ATTEMPTED_ACTION=$(sed -n '/## Attempted Action/,/## Error Details/p' "$BLOCKED_FILE" | sed '1d;$d' | sed '/^$/d')
ERROR_DETAILS=$(sed -n '/## Error Details/,/## Guidance Needed/p' "$BLOCKED_FILE" | sed '1d;$d' | sed '/^$/d')

cat > "$GUIDANCE_FILE" << EOF
---
stream: $STREAM_ID
guidance_type: workaround
provided: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# Stream $STREAM_ID Recovery Guidance

## Context
**Original Issue:** $REASON
**What Was Attempted:** $ATTEMPTED_ACTION
**Error Details:** $ERROR_DETAILS

## Approach
{Describe the alternative approach to take instead of the blocked action}

## Specific Instructions
1. {First step to work around the blockage}
2. {Second step}
3. {Additional steps as needed}

## Acceptable Outcomes
- {What partial completion is acceptable}
- {What functionality can be deferred}

## Do Not Attempt
- {What should definitely be avoided to prevent the same blockage}

## Notes
{Any additional context or considerations for the recovery agent}

EOF

echo "Guidance template created: $GUIDANCE_FILE"
echo ""
echo "Edit this file with specific instructions, then run:"
echo "  /pm:epic-retry $EPIC_NAME"