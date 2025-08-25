#!/bin/bash
# Check for guidance files and stream status
EPIC_NAME=$1

if [ -z "$EPIC_NAME" ]; then
    echo "Usage: coordination-check.sh <epic-name>"
    exit 1
fi

COORDINATION_DIR=".claude/epics/$EPIC_NAME/coordination"

if [ ! -d "$COORDINATION_DIR" ]; then
    echo "No coordination directory found for epic: $EPIC_NAME"
    exit 1
fi

echo "Checking coordination status for epic: $EPIC_NAME"
echo "==============================================="

# Check for blocked streams
BLOCKED_COUNT=0
READY_COUNT=0
WAITING_COUNT=0

for blocked in $COORDINATION_DIR/stream-*-blocked.md; do
    [ -f "$blocked" ] || continue
    
    STREAM=$(basename $blocked | sed 's/stream-//' | sed 's/-blocked.md//')
    GUIDANCE="$COORDINATION_DIR/stream-$STREAM-guidance.md"
    
    if [ -f "$GUIDANCE" ]; then
        echo "READY:$STREAM"
        READY_COUNT=$((READY_COUNT + 1))
    else
        echo "WAITING:$STREAM"
        WAITING_COUNT=$((WAITING_COUNT + 1))
    fi
    
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
done

echo ""
echo "Summary:"
echo "- Total blocked streams: $BLOCKED_COUNT"
echo "- Ready for retry: $READY_COUNT"
echo "- Awaiting guidance: $WAITING_COUNT"

if [ $WAITING_COUNT -gt 0 ]; then
    echo ""
    echo "Streams awaiting guidance:"
    for blocked in $COORDINATION_DIR/stream-*-blocked.md; do
        [ -f "$blocked" ] || continue
        
        STREAM=$(basename $blocked | sed 's/stream-//' | sed 's/-blocked.md//')
        GUIDANCE="$COORDINATION_DIR/stream-$STREAM-guidance.md"
        
        if [ ! -f "$GUIDANCE" ]; then
            echo "  - Stream $STREAM: Create $COORDINATION_DIR/stream-$STREAM-guidance.md"
        fi
    done
fi

if [ $READY_COUNT -gt 0 ]; then
    echo ""
    echo "Ready to retry with: /pm:epic-retry $EPIC_NAME"
fi