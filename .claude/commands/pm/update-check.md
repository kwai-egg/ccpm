# Command: /pm:update-check

## Purpose
Check for available Claude Code PM system updates without applying them, showing version differences and file changes.

## Parameters
- `--verbose`: Optional flag - Show detailed information about changes
- `--quiet`: Optional flag - Show minimal output, suitable for automation

## Prerequisites
- Git repository with `.claude-pm.yaml` configuration
- Internet connection to check upstream repository
- Valid upstream repository configured

## Implementation

### Phase 1: Environment Validation
```bash
# Change to project root
cd "$(git rev-parse --show-toplevel)" || error "Not in a git repository"

# Check configuration exists
test -f ".claude-pm.yaml" || error "Configuration missing. Run '/pm:init' first"

# Validate upstream configuration
upstream_url=$(grep "upstream:" ".claude-pm.yaml" | cut -d'"' -f2)
test -n "$upstream_url" || error "No upstream URL configured"
```

### Phase 2: Update Check Execution
```bash
# Execute update check script
if [[ "$VERBOSE" == true ]]; then
    ./.claude/scripts/pm/update-check.sh --verbose
elif [[ "$QUIET" == true ]]; then
    ./.claude/scripts/pm/update-check.sh --quiet
else
    ./.claude/scripts/pm/update-check.sh
fi

# Capture exit code to determine if updates are available
update_available=$?
```

### Phase 3: Action Recommendations
```bash
case $update_available in
    0)
        echo "✅ System is up to date"
        echo "Current version: $(cat .claude/VERSION 2>/dev/null || echo 'unknown')"
        ;;
    1)
        echo "🔄 Updates available!"
        echo "Run '/pm:update' to apply updates"
        echo "Run '/pm:update --dry-run' to see what would change"
        ;;
    2)
        echo "⚠️  Cannot determine update status"
        echo "You may want to run '/pm:update' to ensure latest version"
        ;;
esac
```

## Examples

### Basic Update Check
```bash
/pm:update-check
```
Shows current version, upstream version, and whether updates are available.

### Verbose Check
```bash
/pm:update-check --verbose
```
Shows detailed changelog and file-by-file changes.

### Quiet Check (for automation)
```bash
/pm:update-check --quiet
```
Minimal output suitable for scripts and automation.

## Output Format

### Standard Output
```
🔍 Claude Code PM Update Check

ℹ️  Current version: 1.0.0
ℹ️  Upstream version: 1.1.0

📋 Changes Available:
## [1.1.0] - 2025-08-26
### Added
- New update system functionality
- Enhanced backup and restore capabilities

📁 Files That Would Be Updated:
  ✅ .claude/agents/parallel-worker.md (will be updated)
  ✅ .claude/commands/pm/update.md (will be updated)
  ⏭️  .claude/context/progress.md (preserved - no changes)

📊 Update Status Summary:
⚠️  Update available: 1.0.0 -> 1.1.0
ℹ️  Run '/pm:update' to apply updates
```

### Verbose Output
Includes additional information:
- Full changelog entries
- Detailed file differences
- Merge strategy for each file
- Backup and restore information

### Quiet Output
```
UPDATE_AVAILABLE=1
CURRENT_VERSION=1.0.0
UPSTREAM_VERSION=1.1.0
```

## Exit Codes

- **0**: No updates available or already up to date
- **1**: Updates are available
- **2**: Cannot determine update status (network issues, configuration problems)

## Error Handling

### Network Issues
- **No internet connection**: Shows cached information if available
- **Upstream unreachable**: Suggests checking configuration
- **Authentication required**: Guides user through GitHub authentication

### Configuration Issues
- **Missing .claude-pm.yaml**: Instructions to run `/pm:init`
- **Invalid upstream URL**: Suggests fixing configuration
- **Corrupted local state**: Recommends running `/pm:validate`

## Integration with Other Tools

### Shell Scripts
```bash
if /pm:update-check --quiet; then
    echo "System up to date"
else
    echo "Updates available, consider running /pm:update"
fi
```

### CI/CD Pipelines
```yaml
- name: Check for PM updates
  run: |
    if /pm:update-check --quiet; then
      echo "::notice::Claude Code PM is up to date"
    else
      echo "::warning::Claude Code PM updates available"
    fi
```

### Automated Updates
```bash
# Check and update if available
if ! /pm:update-check --quiet; then
    /pm:update --confirm
fi
```

## Configuration

Uses settings from `.claude-pm.yaml`:
```yaml
upstream: https://github.com/kwai-egg/ccpm.git
branch: main
```

Can be overridden with environment variables:
```bash
CCPM_UPSTREAM_URL=https://github.com/custom/ccpm.git /pm:update-check
CCPM_UPSTREAM_BRANCH=develop /pm:update-check
```

## Related Commands
- `/pm:update` - Apply available updates
- `/pm:update --dry-run` - Preview update changes
- `/pm:update-status` - Show current system status
- `/pm:validate` - Verify system integrity