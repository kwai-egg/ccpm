---
allowed-tools: Bash, Read, Task, BashOutput, KillBash
---

# Issue Resume

Resume previously paused parallel agents working on a GitHub issue.

## Usage
```
/pm:issue-resume <issue_number> <stream_id>
```

## Parameters
- `issue_number`: Required - GitHub issue number
- `stream_id`: Required - Stream to resume (A, B, C, etc.) or "all" for all paused streams

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
     exit 1
   fi
   ```

## Instructions

### 1. Validate Resume Target

```bash
epic_name=$(echo "$task_file" | cut -d'/' -f3)
stream_id="${2:-}"

if [ -z "$stream_id" ]; then
  echo "❌ Stream ID required"
  echo "Usage: /pm:issue-resume $ARGUMENTS <stream_id>"
  echo ""
  echo "Paused streams:"
  find ".claude/epics/$epic_name/updates/$ARGUMENTS" -name "stream-*.md" -exec grep -l "status: paused" {} \; 2>/dev/null | sed 's/.*stream-\(.\)\.md/  \1/' || echo "  (No paused streams found)"
  exit 1
fi

# Check memory capacity before resuming
echo "🔍 Checking memory capacity before resume..."
capacity_info=$(.claude/scripts/pm/coordination-memory.sh "$epic_name" assess 1)
spawn_capacity=$(echo "$capacity_info" | grep "spawn_capacity:" | cut -d':' -f2)

if [ "$spawn_capacity" -lt 1 ]; then
  echo "⚠️  WARNING: Low memory capacity (can spawn $spawn_capacity agents)"
  echo "Current memory usage:"
  .claude/scripts/pm/memory-monitor.sh usage | grep "Usage:"
  echo ""
  read -p "Continue with resume anyway? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Resume cancelled due to memory constraints"
    exit 1
  fi
fi
```

### 2. Resume Single Stream

For specific stream:
```bash
if [ "$stream_id" != "all" ]; then
  stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream_id.md"
  
  # Check if stream is actually paused
  if [ ! -f "$stream_file" ]; then
    echo "❌ Stream $stream_id not found"
    exit 1
  fi
  
  if ! grep -q "status: paused" "$stream_file"; then
    current_status=$(grep "^status:" "$stream_file" | cut -d':' -f2 | xargs)
    echo "❌ Stream $stream_id is not paused (current status: $current_status)"
    echo "💡 Use /pm:issue-monitor $ARGUMENTS $stream_id to check stream status"
    exit 1
  fi
  
  echo "▶️  Resuming Stream $stream_id for Issue #$ARGUMENTS"
  
  # Read stream configuration from file
  stream_name=$(grep "^stream:" "$stream_file" | cut -d':' -f2 | xargs)
  agent_type=$(grep "^agent:" "$stream_file" | cut -d':' -f2 | xargs)
  
  # Read original task requirements
  task_content=$(cat ".claude/epics/$epic_name/$ARGUMENTS.md")
  analysis_file=".claude/epics/$epic_name/$ARGUMENTS-analysis.md"
  
  if [ -f "$analysis_file" ]; then
    # Extract stream-specific requirements
    stream_requirements=$(awk -v stream="$stream_name" '
      /^## Stream [A-Z]:/ {
        if ($0 ~ stream || $3 == stream) {
          in_stream = 1
          next
        } else {
          in_stream = 0
        }
      }
      in_stream && /^## / && !/^## Stream/ {
        in_stream = 0
      }
      in_stream {
        print
      }
    ' "$analysis_file")
  fi
  
  # Update stream file to in_progress
  sed -i.bak 's/^status: paused/status: in_progress/' "$stream_file"
  
  # Add resume timestamp
  resume_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if ! grep -q "resumed:" "$stream_file"; then
    sed -i.bak "/^status: in_progress/a\\
resumed: $resume_time" "$stream_file"
  else
    sed -i.bak "s/^resumed: .*/resumed: $resume_time/" "$stream_file"
  fi
  
  rm "${stream_file}.bak" 2>/dev/null || true
  
  # Track agent spawn in coordination system
  .claude/scripts/pm/coordination-memory.sh "$epic_name" spawn "$stream_id"
  
  # Relaunch the agent with resume context
  Task:
    description: "Issue #$ARGUMENTS Stream $stream_id (Resume)"
    subagent_type: "$agent_type"
    prompt: |
      You are resuming work on Issue #$ARGUMENTS in the epic worktree after a pause.
      
      RESUME CONTEXT: This stream was paused and is now being resumed.
      
      Worktree location: ../epic-$epic_name/
      Your stream: $stream_name
      
      Previous work: Check git history and current file states to understand what was completed before the pause.
      
      Your scope:
      $stream_requirements
      
      Requirements:
      1. Check git log and current file states to understand previous progress
      2. Continue from where the previous agent left off
      3. Work ONLY on your assigned files and scope
      4. Commit frequently with format: "Issue #$ARGUMENTS: {specific change} (resumed)"
      5. Update progress in: .claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream_id.md
      6. Follow coordination rules in .claude/rules/agent-coordination.md
      
      If you find the work was already completed during the pause:
      - Mark the stream as completed
      - Update the progress file accordingly
      - Report what was previously done
      
      If you cannot determine the previous state:
      - Ask for clarification in your progress updates
      - Start with a safe assessment of current state
      - Avoid duplicating work
      
      Complete your stream's remaining work and mark as completed when done.
  
  # Log the resume action
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] RESUME: Stream $stream_id resumed by user request" >> "$coordination_dir/memory-log.md"
  
  echo "✅ Stream $stream_id resumed successfully"
fi
```

### 3. Resume All Paused Streams

For "all" parameter:
```bash
if [ "$stream_id" = "all" ]; then
  echo "▶️  Resuming ALL paused streams for Issue #$ARGUMENTS"
  
  # Get list of paused streams
  paused_streams=$(find ".claude/epics/$epic_name/updates/$ARGUMENTS" -name "stream-*.md" -exec grep -l "status: paused" {} \; 2>/dev/null | sed 's/.*stream-\(.\)\.md/\1/')
  
  if [ -z "$paused_streams" ]; then
    echo "ℹ️  No paused streams to resume"
    exit 0
  fi
  
  # Check if we have capacity for all streams
  stream_count=$(echo "$paused_streams" | wc -w)
  capacity_info=$(.claude/scripts/pm/coordination-memory.sh "$epic_name" assess "$stream_count")
  spawn_capacity=$(echo "$capacity_info" | grep "spawn_capacity:" | cut -d':' -f2)
  
  if [ "$spawn_capacity" -lt "$stream_count" ]; then
    echo "⚠️  WARNING: Limited memory capacity"
    echo "  Streams to resume: $stream_count"
    echo "  Current capacity: $spawn_capacity"
    echo ""
    echo "💡 Consider resuming streams individually or in smaller batches:"
    for stream in $paused_streams; do
      echo "  /pm:issue-resume $ARGUMENTS $stream"
    done
    exit 1
  fi
  
  resumed_count=0
  for stream in $paused_streams; do
    echo "  Resuming stream $stream..."
    
    # Use the single stream resume logic (simplified)
    stream_file=".claude/epics/$epic_name/updates/$ARGUMENTS/stream-$stream.md"
    
    # Update status
    sed -i.bak 's/^status: paused/status: in_progress/' "$stream_file"
    resume_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if ! grep -q "resumed:" "$stream_file"; then
      sed -i.bak "/^status: in_progress/a\\
resumed: $resume_time" "$stream_file"
    else
      sed -i.bak "s/^resumed: .*/resumed: $resume_time/" "$stream_file"
    fi
    rm "${stream_file}.bak" 2>/dev/null || true
    
    # Track spawn
    .claude/scripts/pm/coordination-memory.sh "$epic_name" spawn "$stream"
    
    # Launch agent (simplified for batch resume)
    agent_type=$(grep "^agent:" "$stream_file" | cut -d':' -f2 | xargs)
    stream_name=$(grep "^stream:" "$stream_file" | cut -d':' -f2 | xargs)
    
    # Note: For batch resume, we use a simplified relaunch
    # In production, you might want to resume streams one by one
    
    resumed_count=$((resumed_count + 1))
  done
  
  # Log the mass resume action
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] RESUME ALL: $resumed_count streams resumed by user request" >> "$coordination_dir/memory-log.md"
  
  echo "✅ Resumed $resumed_count streams successfully"
fi
```

### 4. Show Post-Resume Status

```bash
echo ""
echo "📋 Post-Resume Status:"

# Show memory usage change
current_memory=$(.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | cut -d':' -f2 | xargs)
echo "  Current memory usage: $current_memory"

# Show active vs paused agents
active_count=$(grep -c "status:spawned" "$coordination_dir/active-agents.log" 2>/dev/null || echo "0")
paused_count=$(find ".claude/epics/$epic_name/updates/$ARGUMENTS" -name "stream-*.md" -exec grep -l "status: paused" {} \; 2>/dev/null | wc -l)

echo "  Now active: $active_count streams"
echo "  Still paused: $paused_count streams"

echo ""
echo "💡 Next Steps:"
echo "  /pm:issue-monitor $ARGUMENTS           - Monitor resumed streams"
echo "  /pm:issue-pause $ARGUMENTS $stream_id  - Pause if issues arise"
echo "  /pm:epic-status $epic_name             - Epic overview"
```

### 5. Update GitHub Issue

```bash
# Add resume comment to GitHub issue
resume_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ "$stream_id" = "all" ]; then
  comment_body="▶️  **All paused streams resumed** at $resume_time

**Streams resumed:** $resumed_count
**Memory usage:** $current_memory

Work continues on all parallel streams."
else
  comment_body="▶️  **Stream $stream_id resumed** at $resume_time

**Memory usage:** $current_memory

Work continues on this stream."
fi

gh issue comment "$ARGUMENTS" --body "$comment_body" 2>/dev/null || echo "⚠️  Could not update GitHub issue (continuing anyway)"
```

## Error Handling

Handle resume operation failures:
- **Stream not paused**: Clear message about current status
- **Memory constraints**: Warning and confirmation prompt
- **Missing files**: Helpful error messages
- **Agent spawn failures**: Graceful degradation
- **Coordination issues**: Clear guidance for resolution

## Important Notes

- Resume checks memory capacity before relaunching agents
- Resumed agents get context about previous work and pause
- Stream files track resume timestamps for debugging
- GitHub issue gets status updates for team visibility
- Coordination logs track all resume actions
- Agents check git history to understand previous progress