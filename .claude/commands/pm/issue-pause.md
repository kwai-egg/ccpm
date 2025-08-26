---
allowed-tools: Bash, Read, BashOutput, KillBash
---

# Issue Pause

Pause specific parallel agents working on a GitHub issue.

## Usage
```
/pm:issue-pause <issue_number> <stream_id>
```

## Parameters
- `issue_number`: Required - GitHub issue number
- `stream_id`: Required - Stream to pause (A, B, C, etc.) or "all" for all streams

## Quick Check

1. **Verify issue exists locally:**
   ```bash
   task_file=$(find .claude/epics -name "$ARGUMENTS.md" 2>/dev/null | head -1)
   if [ -z "$task_file" ]; then
     echo "❌ No local task found for issue #$ARGUMENTS"
     exit 1
   fi
   ```

2. **Check coordination directory:**
   ```bash
   epic_name=$(echo "$task_file" | cut -d'/' -f3)
   coordination_dir=".claude/epics/$epic_name/coordination"
   
   if [ ! -d "$coordination_dir" ]; then
     echo "❌ No coordination directory found. Issue may not be started yet."
     echo "💡 Try: /pm:issue-start $ARGUMENTS"
     exit 1
   fi
   ```

## Instructions

### 1. Validate Stream Target

```bash
epic_name=$(echo "$task_file" | cut -d'/' -f3)
stream_id="${2:-}"

if [ -z "$stream_id" ]; then
  echo "❌ Stream ID required"
  echo "Usage: /pm:issue-pause $ARGUMENTS <stream_id>"
  echo ""
  echo "Available streams:"
  if [ -f "$coordination_dir/active-agents.log" ]; then
    grep "^stream_id:" "$coordination_dir/active-agents.log" | cut -d':' -f2 | sed 's/^/  /'
  else
    echo "  (No active agents found)"
  fi
  exit 1
fi

# Validate stream exists (unless "all")
if [ "$stream_id" != "all" ]; then
  if ! grep -q "stream_id:$stream_id" "$coordination_dir/active-agents.log" 2>/dev/null; then
    echo "❌ Stream $stream_id not found in active agents"
    echo "Available streams:"
    grep "^stream_id:" "$coordination_dir/active-agents.log" 2>/dev/null | cut -d':' -f2 | sed 's/^/  /' || echo "  (None active)"
    exit 1
  fi
fi
```

### 2. Pause Single Stream

For specific stream:
```bash
if [ "$stream_id" != "all" ]; then
  echo "⏸️  Pausing Stream $stream_id for Issue #$ARGUMENTS"
  
  # Use coordination-memory.sh to pause the stream
  .claude/scripts/pm/coordination-memory.sh "$epic_name" pause "$stream_id"
  
  # Update stream status file if it exists
  stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream_id.md"
  if [ -f "$stream_file" ]; then
    # Update frontmatter status
    sed -i.bak 's/^status: in_progress/status: paused/' "$stream_file"
    
    # Add pause timestamp
    pause_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if ! grep -q "paused:" "$stream_file"; then
      sed -i.bak "/^status: paused/a\\
paused: $pause_time" "$stream_file"
    else
      sed -i.bak "s/^paused: .*/paused: $pause_time/" "$stream_file"
    fi
    
    rm "${stream_file}.bak" 2>/dev/null || true
  fi
  
  # Log the pause action
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] PAUSE: Stream $stream_id paused by user request" >> "$coordination_dir/memory-log.md"
  
  echo "✅ Stream $stream_id paused successfully"
  
  # Show what the stream was doing
  echo ""
  echo "📊 Stream $stream_id Status Before Pause:"
  awk -v target="$stream_id" '
    /^stream_id:/ {
      if (substr($0, 11) == target) {
        in_target = 1
        print "  Stream: " substr($0, 11)
      } else {
        in_target = 0
      }
      next
    }
    in_target && /^---$/ {
      in_target = 0
      next
    }
    in_target {
      print "  " $0
    }
  ' "$coordination_dir/active-agents.log"
fi
```

### 3. Pause All Streams

For "all" parameter:
```bash
if [ "$stream_id" = "all" ]; then
  echo "⏸️  Pausing ALL streams for Issue #$ARGUMENTS"
  
  # Get list of active streams
  active_streams=$(grep "^stream_id:" "$coordination_dir/active-agents.log" 2>/dev/null | cut -d':' -f2)
  
  if [ -z "$active_streams" ]; then
    echo "ℹ️  No active streams to pause"
    exit 0
  fi
  
  paused_count=0
  for stream in $active_streams; do
    echo "  Pausing stream $stream..."
    
    # Use coordination-memory.sh to pause each stream
    .claude/scripts/pm/coordination-memory.sh "$epic_name" pause "$stream"
    
    # Update stream status file if it exists
    stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream.md"
    if [ -f "$stream_file" ]; then
      sed -i.bak 's/^status: in_progress/status: paused/' "$stream_file"
      
      pause_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      if ! grep -q "paused:" "$stream_file"; then
        sed -i.bak "/^status: paused/a\\
paused: $pause_time" "$stream_file"
      else
        sed -i.bak "s/^paused: .*/paused: $pause_time/" "$stream_file"
      fi
      
      rm "${stream_file}.bak" 2>/dev/null || true
    fi
    
    paused_count=$((paused_count + 1))
  done
  
  # Log the mass pause action
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] PAUSE ALL: $paused_count streams paused by user request" >> "$coordination_dir/memory-log.md"
  
  echo "✅ Paused $paused_count streams successfully"
fi
```

### 4. Show Post-Pause Status

```bash
echo ""
echo "📋 Post-Pause Status:"

# Show memory usage change
current_memory=$(.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | cut -d':' -f2 | xargs)
echo "  Current memory usage: $current_memory"

# Show active vs paused agents
active_count=$(grep -c "status:spawned" "$coordination_dir/active-agents.log" 2>/dev/null || echo "0")
paused_count=$(find ".claude/epics/$epic_name/updates/$ARGUMENTS" -name "stream-*.md" -exec grep -l "status: paused" {} \; 2>/dev/null | wc -l)

echo "  Still active: $active_count streams"
echo "  Now paused: $paused_count streams"

# Show worktree status
if [ -d "../epic-$epic_name" ]; then
  cd "../epic-$epic_name"
  uncommitted=$(git status --porcelain | wc -l)
  echo "  Uncommitted changes: $uncommitted files"
  cd - >/dev/null
fi

echo ""
echo "💡 Next Steps:"
echo "  /pm:issue-monitor $ARGUMENTS           - Monitor remaining active streams"
echo "  /pm:issue-resume $ARGUMENTS $stream_id - Resume paused stream"
echo "  /pm:issue-kill $ARGUMENTS $stream_id   - Kill problematic stream"
```

### 5. Update GitHub Issue

```bash
# Add pause comment to GitHub issue
pause_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ "$stream_id" = "all" ]; then
  comment_body="⏸️  **All parallel streams paused** at $pause_time

**Reason:** User requested pause (likely for debugging/inspection)

**Streams paused:** $(echo "$active_streams" | wc -w)
**Memory usage:** $current_memory

Use \`/pm:issue-resume $ARGUMENTS <stream>\` to resume specific streams."
else
  comment_body="⏸️  **Stream $stream_id paused** at $pause_time

**Reason:** User requested pause (likely for debugging/inspection)

**Memory usage:** $current_memory

Use \`/pm:issue-resume $ARGUMENTS $stream_id\` to resume this stream."
fi

gh issue comment "$ARGUMENTS" --body "$comment_body" 2>/dev/null || echo "⚠️  Could not update GitHub issue (continuing anyway)"
```

## Error Handling

Handle pause operation failures:
- **Stream not found**: Show available streams
- **Already paused**: Detect and handle gracefully
- **Coordination issues**: Clear error messages
- **File permission problems**: Helpful guidance
- **GitHub API failures**: Continue with local pause

## Important Notes

- Pausing stops the agent execution but preserves all state
- Stream files are updated with pause timestamp
- Memory usage should decrease after pausing agents
- GitHub issue gets status comment for team visibility
- Coordination logs track all pause actions for debugging