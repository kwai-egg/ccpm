---
allowed-tools: Bash, Read, Write, Edit, Task, Glob, Grep, LS
---

# Epic Retry

Retry blocked streams with user guidance.

## Usage
/pm:epic-retry {epic-name}

## Instructions

This command retries streams that were blocked during parallel execution and now have user-provided guidance files.

**Implementation Steps:**

1. **Validate Epic Exists**
   - Check that .claude/epics/{epic-name} exists
   - Verify coordination directory exists
   - Exit with helpful message if not found

2. **Check Coordination Status**
   - Use coordination-check.sh to identify streams ready for retry
   - List streams awaiting guidance (if any)
   - Exit if no streams are ready for retry

3. **Read Stream Context**
   For each stream ready for retry:
   - Read the original task file requirements
   - Read the blocked status file for failure context
   - Read the user-provided guidance file
   - Prepare recovery context

4. **Launch Recovery Agents**
   For each stream with guidance:
   - Use Task tool with subagent_type: "general-purpose"
   - Include original requirements, failure context, and user guidance
   - Set maximum 2 retry attempts per stream
   - Track recovery attempts in coordination directory

5. **Monitor Recovery Results**
   - Wait for all recovery agents to complete
   - Update coordination status based on results
   - Mark successfully recovered streams as complete
   - Create new blocked files for streams that still fail

6. **Report Results**
   - Summary of recovered streams
   - Remaining blocked streams (if any)
   - Next actions needed

## Recovery Agent Prompt Template

When launching recovery agents, use this template:

```
You are recovering a blocked work stream in worktree: {worktree_path}

**PREVIOUS ATTEMPT FAILED:**
{failure_reason_from_blocked_file}

**USER GUIDANCE:**
{content_from_guidance_file}

**ORIGINAL REQUIREMENTS:**
{requirements_from_task_file}

**Stream Details:**
- Stream: {stream_name}
- Attempt: {attempt_number} of 2
- Files affected: {affected_files}

**Instructions:**
1. Follow the user's guidance to work around the blockage
2. Implement alternative approaches as suggested
3. If you still cannot proceed, clearly explain why
4. Complete as much as possible given the constraints
5. Make commits in format: "Issue #{number}: Recovery {stream_name} - {specific_change}"

**Return Format:**
- **Completed:** {what you accomplished}
- **Files Modified:** {list of files changed}
- **Remaining Blockers:** {any issues still preventing completion}
- **Test Results:** {if applicable}
- **Recovery Status:** {SUCCESS/PARTIAL/FAILED}
```

## Error Handling

- If epic doesn't exist: Show available epics
- If no coordination directory: Suggest running the original parallel command first
- If no blocked streams: Confirm all streams completed successfully
- If guidance files are malformed: Show template and ask user to fix
- If recovery agents fail: Create detailed failure reports for debugging

## Success Criteria

The command succeeds when:
- All streams with guidance are successfully retried
- Coordination status is updated accurately
- Clear next steps are provided to user
- System is ready for further work or completion