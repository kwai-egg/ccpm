#!/bin/bash
# Mark a stream as blocked
EPIC_NAME=$1
STREAM_ID=$2
REASON=$3
ATTEMPTED_ACTION=$4
ERROR_DETAILS=$5

if [ -z "$EPIC_NAME" ] || [ -z "$STREAM_ID" ] || [ -z "$REASON" ]; then
    echo "Usage: coordination-block.sh <epic-name> <stream-id> <reason> [attempted-action] [error-details]"
    exit 1
fi

# Ensure coordination directory exists
mkdir -p .claude/epics/$EPIC_NAME/coordination

cat > .claude/epics/$EPIC_NAME/coordination/stream-$STREAM_ID-blocked.md << EOF
---
stream: $STREAM_ID
status: blocked
reason: $REASON
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
awaiting_guidance: true
---

## Attempted Action
${ATTEMPTED_ACTION:-"Not specified"}

## Error Details
${ERROR_DETAILS:-"Not specified"}

## Guidance Needed
Please edit stream-$STREAM_ID-guidance.md with instructions on how to proceed.

To provide guidance:
1. Create .claude/epics/$EPIC_NAME/coordination/stream-$STREAM_ID-guidance.md
2. Provide alternative approaches or workarounds
3. Run: /pm:epic-retry $EPIC_NAME
EOF

echo "Stream $STREAM_ID marked as blocked for epic: $EPIC_NAME"
echo "Guidance file needed: .claude/epics/$EPIC_NAME/coordination/stream-$STREAM_ID-guidance.md"