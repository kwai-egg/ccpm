---
allowed-tools: Bash, Read, BashOutput, KillBash
---

# Issue Kill

Kill runaway or problematic parallel agents working on a GitHub issue.

## Usage
```
/pm:issue-kill <issue_number> <stream_id>
```

## Parameters
- `issue_number`: Required - GitHub issue number
- `stream_id`: Required - Stream to kill (A, B, C, etc.) or "all" for emergency shutdown

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
     echo "❌ No coordination directory found. Issue may not be active."
     exit 1
   fi
   ```

## Instructions

### 1. Validate Kill Target

```bash
epic_name=$(echo "$task_file" | cut -d'/' -f3)
stream_id="${2:-}"

if [ -z "$stream_id" ]; then
  echo "❌ Stream ID required"
  echo "Usage: /pm:issue-kill $ARGUMENTS <stream_id|all>"
  echo ""
  echo "Active streams:"
  if [ -f "$coordination_dir/active-agents.log" ]; then
    grep "^stream_id:" "$coordination_dir/active-agents.log" | cut -d':' -f2 | sed 's/^/  /'
  else
    echo "  (No active agents found)"
  fi
  exit 1
fi

# Show warning for kill operation
if [ "$stream_id" = "all" ]; then
  echo "⚠️  WARNING: This will kill ALL active streams for issue #$ARGUMENTS"
else
  echo "⚠️  WARNING: This will kill stream $stream_id for issue #$ARGUMENTS"
fi

echo "This action cannot be undone. The agents will be terminated immediately."
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "❌ Kill operation cancelled"
  exit 0
fi
```

### 2. Kill Single Stream

For specific stream:
```bash
if [ "$stream_id" != "all" ]; then
  echo "💀 Killing Stream $stream_id for Issue #$ARGUMENTS"
  
  # Check if stream is active
  if ! grep -q "stream_id:$stream_id" "$coordination_dir/active-agents.log" 2>/dev/null; then
    echo "ℹ️  Stream $stream_id not found in active agents (may already be stopped)"
  else
    # Use coordination-memory.sh to kill the stream
    ~/.claude/scripts/pm/coordination-memory.sh "$epic_name" kill "$stream_id"
    
    # Find and kill any background processes related to this stream
    # Look for processes with stream ID or issue number
    pkill -f "issue.*$ARGUMENTS.*stream.*$stream_id" 2>/dev/null || true
    pkill -f "stream.*$stream_id.*issue.*$ARGUMENTS" 2>/dev/null || true
    
    # Update coordination tracking
    ~/.claude/scripts/pm/coordination-memory.sh "$epic_name" complete "$stream_id" "killed"
  fi
  
  # Update stream status file if it exists
  stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream_id.md"
  if [ -f "$stream_file" ]; then
    # Update frontmatter status
    sed -i.bak 's/^status: in_progress/status: killed/' "$stream_file"
    sed -i.bak 's/^status: paused/status: killed/' "$stream_file"
    
    # Add kill timestamp
    kill_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if ! grep -q "killed:" "$stream_file"; then
      sed -i.bak "/^status: killed/a\\
killed: $kill_time" "$stream_file"
    else
      sed -i.bak "s/^killed: .*/killed: $kill_time/" "$stream_file"
    fi
    
    rm "${stream_file}.bak" 2>/dev/null || true
  fi
  
  # Log the kill action
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] KILL: Stream $stream_id killed by user request" >> "$coordination_dir/memory-log.md"
  
  echo "💀 Stream $stream_id killed successfully"
  
  # Show what was killed
  echo ""
  echo "📊 Killed Stream Info:"
  echo "  Stream: $stream_id"
  echo "  Status: Terminated"
  echo "  Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi
```

### 3. Emergency Kill All Streams

For "all" parameter:
```bash
if [ "$stream_id" = "all" ]; then
  echo "💀 EMERGENCY KILL: Terminating ALL streams for Issue #$ARGUMENTS"
  
  # Get list of active streams
  active_streams=$(grep "^stream_id:" "$coordination_dir/active-agents.log" 2>/dev/null | cut -d':' -f2)
  
  if [ -z "$active_streams" ]; then
    echo "ℹ️  No active streams found to kill"
  else
    killed_count=0
    
    # Kill all processes first
    echo "  Terminating background processes..."
    pkill -f "issue.*$ARGUMENTS" 2>/dev/null || true
    pkill -f "parallel.*worker.*$ARGUMENTS" 2>/dev/null || true
    pkill -f "epic.*coordination.*$epic_name" 2>/dev/null || true
    
    # Process each stream
    for stream in $active_streams; do
      echo "  Killing stream $stream..."
      
      # Use coordination-memory.sh to kill each stream
      ~/.claude/scripts/pm/coordination-memory.sh "$epic_name" kill "$stream"
      ~/.claude/scripts/pm/coordination-memory.sh "$epic_name" complete "$stream" "killed"
      
      # Update stream status file
      stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream.md"
      if [ -f "$stream_file" ]; then
        sed -i.bak 's/^status: in_progress/status: killed/' "$stream_file"
        sed -i.bak 's/^status: paused/status: killed/' "$stream_file"
        
        kill_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        if ! grep -q "killed:" "$stream_file"; then
          sed -i.bak "/^status: killed/a\\
killed: $kill_time" "$stream_file"
        else
          sed -i.bak "s/^killed: .*/killed: $kill_time/" "$stream_file"
        fi
        
        rm "${stream_file}.bak" 2>/dev/null || true
      fi
      
      killed_count=$((killed_count + 1))
    done
    
    # Force memory cleanup
    echo "  Performing memory cleanup..."
    ~/.claude/scripts/pm/coordination-memory.sh "$epic_name" cleanup
    
    # Log the emergency kill
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] EMERGENCY KILL: $killed_count streams killed by user request" >> "$coordination_dir/memory-log.md"
    
    echo "💀 Emergency kill completed: $killed_count streams terminated"
  fi
fi
```

### 4. Cleanup and Memory Recovery

```bash
echo ""
echo "🧹 Performing post-kill cleanup..."

# Force memory cleanup
~/.claude/scripts/pm/memory-monitor.sh cleanup 2>/dev/null || true

# Clean up coordination tracking
~/.claude/scripts/pm/coordination-memory.sh "$epic_name" cleanup

# Show memory recovery
sleep 2
echo ""
echo "📋 Post-Kill Status:"

current_memory=$(~/.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | cut -d':' -f2 | xargs)
echo "  Current memory usage: $current_memory"

# Count remaining active agents
active_count=$(grep -c "status:spawned" "$coordination_dir/active-agents.log" 2>/dev/null || echo "0")
killed_count=$(find ".claude/epics/$epic_name/updates/$ARGUMENTS" -name "stream-*.md" -exec grep -l "status: killed" {} \; 2>/dev/null | wc -l)

echo "  Remaining active: $active_count streams"
echo "  Killed streams: $killed_count streams"

# Show worktree status
if [ -d "../epic-$epic_name" ]; then
  cd "../epic-$epic_name"
  uncommitted=$(git status --porcelain | wc -l)
  echo "  Uncommitted changes: $uncommitted files"
  cd - >/dev/null
fi

echo ""
echo "💡 Recovery Options:"
if [ "$killed_count" -gt 0 ]; then
  echo "  /pm:issue-start $ARGUMENTS --retry      - Restart killed streams"
  echo "  /pm:issue-analyze $ARGUMENTS            - Re-analyze before restart"
fi
echo "  /pm:epic-status $epic_name              - Check epic status"
echo "  /pm:issue-monitor $ARGUMENTS            - Monitor remaining streams"
```

### 5. Update GitHub Issue

```bash
# Add kill notification to GitHub issue
kill_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ "$stream_id" = "all" ]; then
  comment_body="💀 **EMERGENCY KILL: All streams terminated** at $kill_time

**Reason:** User requested emergency shutdown (likely due to runaway processes or memory issues)

**Streams killed:** $killed_count
**Memory usage after cleanup:** $current_memory

**Next steps:**
- Investigate what caused the need for emergency kill
- Consider running \`/pm:issue-analyze $ARGUMENTS\` before restarting
- Use \`/pm:issue-start $ARGUMENTS --retry\` to restart if needed"
else
  comment_body="💀 **Stream $stream_id killed** at $kill_time

**Reason:** User requested stream termination (likely due to runaway process or memory issues)

**Memory usage after cleanup:** $current_memory

**Next steps:**
- Investigate what caused stream $stream_id to need termination
- Consider restarting this stream individually if needed"
fi

gh issue comment "$ARGUMENTS" --body "$comment_body" 2>/dev/null || echo "⚠️  Could not update GitHub issue (continuing anyway)"
```

### 6. Kill Verification

```bash
echo ""
echo "🔍 Verifying kill completion..."

# Wait a moment for processes to terminate
sleep 3

# Check for any remaining processes
remaining_processes=$(pgrep -f "issue.*$ARGUMENTS" 2>/dev/null | wc -l || echo "0")
if [ "$remaining_processes" -gt 0 ]; then
  echo "⚠️  Warning: $remaining_processes processes may still be running"
  echo "💡 You may need to manually kill them with: pkill -f 'issue.*$ARGUMENTS'"
else
  echo "✅ All processes terminated successfully"
fi

# Verify memory cleanup
memory_after=$(~/.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | cut -d':' -f2 | sed 's/%//')
if [ "$memory_after" -lt 85 ]; then
  echo "✅ Memory usage is normal ($memory_after%)"
else
  echo "⚠️  Memory usage still high ($memory_after%) - may need system restart"
fi
```

## Error Handling

Handle kill operation scenarios:
- **No active streams**: Inform user gracefully
- **Process kill failures**: Show manual cleanup steps
- **File permission issues**: Clear guidance
- **Memory cleanup failures**: Alternative approaches
- **Partial kills**: Report what succeeded/failed

## Important Notes

- Kill is irreversible - agents are terminated immediately
- Requires user confirmation to prevent accidental kills
- Updates all tracking files and coordination logs
- Performs memory cleanup after kill operations
- GitHub issue gets notification for team visibility
- Provides recovery options after kill completion
- Verifies kill completion and suggests manual cleanup if needed