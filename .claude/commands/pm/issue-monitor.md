---
allowed-tools: Bash, Read, BashOutput, KillBash
---

# Issue Monitor

Monitor parallel agents working on a GitHub issue in real-time.

## Usage
```
/pm:issue-monitor <issue_number> [stream_id]
```

## Parameters
- `issue_number`: Required - GitHub issue number being monitored
- `stream_id`: Optional - Specific stream to monitor (A, B, C, etc.). If omitted, monitors all streams

## Quick Check

1. **Verify issue exists locally:**
   ```bash
   # Find task file
   task_file=$(find .claude/epics -name "$ARGUMENTS.md" 2>/dev/null | head -1)
   if [ -z "$task_file" ]; then
     echo "❌ No local task found for issue #$ARGUMENTS"
     exit 1
   fi
   ```

2. **Extract epic name and check coordination:**
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

### 1. Initialize Monitoring

Create monitoring session:
```bash
epic_name=$(echo "$task_file" | cut -d'/' -f3)
monitoring_session="monitor_${ARGUMENTS}_$(date +%s)"

# Start background monitoring process
bash -c "
while true; do
  echo '=== $(date -u +\"%Y-%m-%dT%H:%M:%SZ\") ==='
  ~/.claude/scripts/pm/coordination-memory.sh \"$epic_name\" monitor
  echo ''
  ~/.claude/scripts/pm/memory-monitor.sh usage
  echo ''
  sleep 5
done
" > "/tmp/${monitoring_session}.log" 2>&1 &

monitor_pid=$!
echo "$monitor_pid" > "/tmp/${monitoring_session}.pid"
```

### 2. Display Current Status

Show immediate status:
```bash
echo "🔍 Monitoring Issue #$ARGUMENTS"
echo "Epic: $epic_name"
echo "Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Show active agents
if [ -f "$coordination_dir/active-agents.log" ]; then
  echo "📊 Active Agents:"
  awk '
    /^stream_id:/ { 
      stream = substr($0, 11)
      in_stream = 1
      next
    }
    in_stream && /^spawn_time:/ { 
      spawn_time = substr($0, 12)
      next 
    }
    in_stream && /^status:/ { 
      status = substr($0, 8)
      next
    }
    in_stream && /^---$/ {
      printf "  Stream %s: %s (started: %s)\n", stream, status, spawn_time
      in_stream = 0
      next
    }
  ' "$coordination_dir/active-agents.log"
  echo ""
fi

# Show memory status
echo "💾 System Memory:"
~/.claude/scripts/pm/memory-monitor.sh usage
echo ""

# Show recent coordination events
if [ -f "$coordination_dir/memory-log.md" ]; then
  echo "📝 Recent Events:"
  tail -n 10 "$coordination_dir/memory-log.md" | grep -E '^\[.*\]' | tail -5
  echo ""
fi
```

### 3. Stream-Specific Monitoring

If stream ID provided:
```bash
if [ -n "${2:-}" ]; then
  stream_id="$2"
  echo "🎯 Monitoring Stream $stream_id specifically"
  
  # Check if stream exists
  if ! grep -q "stream_id:$stream_id" "$coordination_dir/active-agents.log" 2>/dev/null; then
    echo "❌ Stream $stream_id not found in active agents"
    echo "Available streams:"
    grep "^stream_id:" "$coordination_dir/active-agents.log" 2>/dev/null | cut -d':' -f2 | sed 's/^/  /'
    exit 1
  fi
  
  # Show stream details
  echo "Stream $stream_id Details:"
  awk -v target="$stream_id" '
    /^stream_id:/ {
      if (substr($0, 11) == target) {
        in_target = 1
        print "  " $0
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
  echo ""
fi
```

### 4. Interactive Monitoring Display

Show continuous updates:
```bash
echo "🚀 Live Monitoring Started"
echo "Press Ctrl+C to stop monitoring"
echo ""

# Monitor the background process output
tail -f "/tmp/${monitoring_session}.log" &
tail_pid=$!

# Cleanup function
cleanup_monitoring() {
  echo ""
  echo "🛑 Stopping monitoring session..."
  
  # Kill background processes
  if [ -f "/tmp/${monitoring_session}.pid" ]; then
    monitor_pid=$(cat "/tmp/${monitoring_session}.pid")
    kill "$monitor_pid" 2>/dev/null || true
    rm "/tmp/${monitoring_session}.pid"
  fi
  
  kill "$tail_pid" 2>/dev/null || true
  rm "/tmp/${monitoring_session}.log" 2>/dev/null || true
  
  echo "✅ Monitoring stopped"
  exit 0
}

# Set trap for cleanup
trap cleanup_monitoring INT TERM

# Wait for user interrupt
wait $tail_pid
```

### 5. Monitoring Summary

Before exit, show final status:
```bash
echo ""
echo "📋 Final Status Summary:"

# Count active vs completed agents
active_count=$(grep -c "status:spawned" "$coordination_dir/active-agents.log" 2>/dev/null || echo "0")
completed_count=$(grep -c "status:completed" "$coordination_dir/active-agents.log" 2>/dev/null || echo "0")

echo "  Active agents: $active_count"
echo "  Completed agents: $completed_count"

# Show memory usage
current_memory=$(~/.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | cut -d':' -f2 | xargs)
echo "  Current memory usage: $current_memory"

# Show worktree status
if [ -d "../epic-$epic_name" ]; then
  cd "../epic-$epic_name"
  uncommitted=$(git status --porcelain | wc -l)
  echo "  Uncommitted changes: $uncommitted files"
  cd - >/dev/null
fi

echo ""
echo "💡 Commands:"
echo "  /pm:issue-pause $ARGUMENTS <stream>  - Pause specific stream"
echo "  /pm:issue-kill $ARGUMENTS <stream>   - Kill specific stream"
echo "  /pm:epic-status $epic_name          - Epic overview"
```

## Error Handling

Handle common monitoring scenarios:
- **No active agents**: Show helpful message about starting work
- **Coordination issues**: Clear messages about fixing coordination problems
- **Permission errors**: Guide user on file access issues
- **Background process failures**: Graceful degradation to manual status checks

## Important Notes

- Uses background processes for continuous monitoring
- Provides both immediate status and live updates
- Graceful cleanup on exit
- Stream-specific monitoring when requested
- Integrates with existing coordination and memory management systems