---
allowed-tools: Bash, Read, Write, LS, Task
---

# Issue Start

Begin work on a GitHub issue with parallel agents based on work stream analysis.

## Usage
```
/pm:issue-start <issue_number>
```

## Quick Check

1. **Get issue details:**
   ```bash
   gh issue view $ARGUMENTS --json state,title,labels,body
   ```
   If it fails: "❌ Cannot access issue #$ARGUMENTS. Check number or run: gh auth login"

2. **Find local task file:**
   - First check if `.claude/epics/*/$ARGUMENTS.md` exists (new naming)
   - If not found, search for file containing `github:.*issues/$ARGUMENTS` in frontmatter (old naming)
   - If not found: "❌ No local task for issue #$ARGUMENTS. This issue may have been created outside the PM system."

3. **Check for analysis:**
   ```bash
   test -f .claude/epics/*/$ARGUMENTS-analysis.md || echo "❌ No analysis found for issue #$ARGUMENTS
   
   Run: /pm:issue-analyze $ARGUMENTS first
   Or: /pm:issue-start $ARGUMENTS --analyze to do both"
   ```
   If no analysis exists and no --analyze flag, stop execution.

## Instructions

### 1. Ensure Worktree Exists

Check if epic worktree exists:
```bash
# Find epic name from task file
epic_name={extracted_from_path}

# Check worktree
if ! git worktree list | grep -q "epic-$epic_name"; then
  echo "❌ No worktree for epic. Run: /pm:epic-start $epic_name"
  exit 1
fi
```

### 2. Read Analysis

Read `.claude/epics/{epic_name}/$ARGUMENTS-analysis.md`:
- Parse parallel streams
- Identify which can start immediately
- Note dependencies between streams

### 3. Setup Progress Tracking

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Create workspace structure:
```bash
mkdir -p .claude/epics/{epic_name}/updates/$ARGUMENTS
```

Update task file frontmatter `updated` field with current datetime.

### 4. Launch Parallel Agents

For each stream that can start immediately:

Create `.claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md`:
```markdown
---
issue: $ARGUMENTS
stream: {stream_name}
agent: {agent_type}
started: {current_datetime}
status: in_progress
---

# Stream {X}: {stream_name}

## Scope
{stream_description}

## Files
{file_patterns}

## Progress
- Starting implementation
```

Launch agent using Task tool:
```yaml
Task:
  description: "Issue #$ARGUMENTS Stream {X}"
  subagent_type: "{agent_type}"
  prompt: |
    You are working on Issue #$ARGUMENTS in the epic worktree.
    
    Worktree location: ../epic-{epic_name}/
    Your stream: {stream_name}
    
    Your scope:
    - Files to modify: {file_patterns}
    - Work to complete: {stream_description}
    
    Requirements:
    1. Read full task from: .claude/epics/{epic_name}/{task_file}
    2. Work ONLY in your assigned files
    3. Commit frequently with format: "Issue #$ARGUMENTS: {specific change}"
    4. Update progress in: .claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md
    5. Follow coordination rules in ~/.claude/rules/agent-coordination.md
    
    If you need to modify files outside your scope:
    - Check if another stream owns them
    - Wait if necessary
    - Update your progress file with coordination notes
    
    Complete your stream's work and mark as completed when done.
```

### 5. Launch Background Monitoring

Start automatic monitoring for the parallel agents:

```bash
# Launch background monitoring using BashOutput
monitoring_session="monitor_${ARGUMENTS}_$(date +%s)"

# Start continuous monitoring in background
Bash:
  description: "Start background monitoring for issue $ARGUMENTS"
  command: |
    # Create monitoring script
    cat > "/tmp/issue_${ARGUMENTS}_monitor.sh" << 'MONITOR_EOF'
    #!/bin/bash
    epic_name="$1"
    issue_num="$2"
    
    while true; do
      echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
      echo "Issue #$issue_num monitoring:"
      
      # Show memory usage
      .claude/scripts/pm/memory-monitor.sh usage | grep -E "Usage:|Available Memory:"
      echo ""
      
      # Show active agents
      coordination_dir=".claude/epics/$epic_name/coordination"
      if [ -f "$coordination_dir/active-agents.log" ]; then
        echo "Active Agents:"
        awk '
          /^stream_id:/ { 
            stream = substr($0, 11)
            in_stream = 1
            next
          }
          in_stream && /^status:/ { 
            status = substr($0, 8)
            printf "  Stream %s: %s\n", stream, status
            next
          }
          in_stream && /^---$/ {
            in_stream = 0
            next
          }
        ' "$coordination_dir/active-agents.log"
      else
        echo "  No active agents found"
      fi
      echo ""
      
      # Check for high memory usage
      current_usage=$(.claude/scripts/pm/memory-monitor.sh usage | grep "Usage:" | sed 's/.*Usage: //' | sed 's/%//')
      if [ "$current_usage" -gt 85 ]; then
        echo "⚠️  HIGH MEMORY WARNING: ${current_usage}% usage"
        echo ""
      fi
      
      sleep 10
    done
    MONITOR_EOF
    
    chmod +x "/tmp/issue_${ARGUMENTS}_monitor.sh"
    "/tmp/issue_${ARGUMENTS}_monitor.sh" "$epic_name" "$ARGUMENTS" > "/tmp/issue_${ARGUMENTS}_monitor.log" 2>&1
  run_in_background: true
  timeout: 0

# Store the monitoring session info
monitoring_pid=$!
echo "monitoring_session:$monitoring_session" >> "$coordination_dir/monitoring.log"
echo "monitoring_pid:$monitoring_pid" >> "$coordination_dir/monitoring.log"
echo "started:$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$coordination_dir/monitoring.log"
echo "issue:$ARGUMENTS" >> "$coordination_dir/monitoring.log"
echo "log_file:/tmp/issue_${ARGUMENTS}_monitor.log" >> "$coordination_dir/monitoring.log"
echo "---" >> "$coordination_dir/monitoring.log"
```

### 6. GitHub Assignment

```bash
# Assign to self and mark in-progress
gh issue edit $ARGUMENTS --add-assignee @me --add-label "in-progress"
```

### 7. Output

```
✅ Started parallel work on issue #$ARGUMENTS

Epic: {epic_name}
Worktree: ../epic-{epic_name}/

Launching {count} parallel agents:
  Stream A: {name} (Agent-1) ✓ Started
  Stream B: {name} (Agent-2) ✓ Started
  Stream C: {name} - Waiting (depends on A)

🔍 Background monitoring started:
  Monitor log: /tmp/issue_{$ARGUMENTS}_monitor.log
  Session: {monitoring_session}

Progress tracking:
  .claude/epics/{epic_name}/updates/$ARGUMENTS/

Real-time commands:
  /pm:issue-monitor $ARGUMENTS           - View live monitoring
  /pm:issue-pause $ARGUMENTS <stream>    - Pause runaway stream
  /pm:issue-kill $ARGUMENTS <stream>     - Kill problematic stream

Status commands:
  /pm:epic-status {epic_name}            - Epic overview
  /pm:issue-sync $ARGUMENTS              - Sync updates to GitHub

Background monitoring will continue automatically. Check /tmp/issue_{$ARGUMENTS}_monitor.log for real-time updates.
```

## Error Handling

If any step fails, report clearly:
- "❌ {What failed}: {How to fix}"
- Continue with what's possible
- Never leave partial state

## Important Notes

Follow `/rules/datetime.md` for timestamps.
Keep it simple - trust that GitHub and file system work.