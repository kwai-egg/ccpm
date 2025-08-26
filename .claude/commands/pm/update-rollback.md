# Command: /pm:update-rollback

## Purpose
Quickly rollback Claude Code PM system to a previous backup, restoring both git state and preserved project files.

## Parameters
- `backup_name`: Required string - Name of the backup to restore (e.g., "backup-20250825-143022")
- `--list`: Optional flag - List all available backups instead of rolling back
- `--confirm`: Optional flag - Skip confirmation prompt

## Prerequisites
- Git repository with backup branches or file backups available
- Backup was created using the Claude Code PM update system
- Clean working directory (uncommitted changes will be lost)

## Implementation

### Phase 1: Validation and Backup Discovery
```bash
# Change to project root
cd "$(git rev-parse --show-toplevel)" || error "Not in a git repository"

# Check if just listing backups
if [[ "$LIST" == true ]]; then
    echo "🗂️  Available Backups:"
    echo ""
    echo "Git Branches:"
    git branch | grep "ccpm-backup-" | sed 's/^[* ] /  /' || echo "  (no backup branches found)"
    
    echo ""
    echo "File Backups:"
    if [[ -d ".ccpm-backups" ]]; then
        ls -1t ".ccpm-backups" | grep "^backup-" | sed 's/^/  /' || echo "  (no file backups found)"
    else
        echo "  (no backup directory found)"
    fi
    exit 0
fi

# Validate backup name provided
test -n "$backup_name" || error "Backup name required. Use '--list' to see available backups"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    if [[ "$CONFIRM" != true ]]; then
        echo "⚠️  You have uncommitted changes that will be lost."
        echo "Continue with rollback? [y/N]"
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] || exit 0
    fi
fi
```

### Phase 2: Backup Verification
```bash
# Check if backup exists
backup_branch="ccpm-backup-$backup_name"
backup_files=".ccpm-backups/$backup_name"

# Verify backup availability
branch_exists=false
files_exist=false

if git show-ref --verify --quiet "refs/heads/$backup_branch"; then
    branch_exists=true
    echo "✅ Found backup branch: $backup_branch"
fi

if [[ -d "$backup_files" ]]; then
    files_exist=true
    echo "✅ Found backup files: $backup_files"
fi

# Must have at least one backup type
if [[ "$branch_exists" == false && "$files_exist" == false ]]; then
    error "No backup found with name: $backup_name"
fi
```

### Phase 3: Rollback Execution
```bash
# Show rollback plan
echo ""
echo "🔄 Rollback Plan:"
if [[ "$branch_exists" == true ]]; then
    echo "  - Restore git state from: $backup_branch"
fi
if [[ "$files_exist" == true ]]; then
    echo "  - Restore project files from: $backup_files"
fi

# Confirm rollback unless --confirm used
if [[ "$CONFIRM" != true ]]; then
    echo ""
    echo "⚠️  This will overwrite current state with backup data."
    echo "Continue with rollback? [y/N]"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || exit 0
fi

# Execute restore script
echo "🚀 Executing rollback..."
.claude/scripts/pm/update-restore.sh "$backup_name"
```

### Phase 4: Post-Rollback Validation
```bash
# Verify rollback success
echo "🔍 Validating rollback..."

# Check critical files exist
critical_files=(".claude/VERSION" ".claude/commands" ".claude/agents")
for file in "${critical_files[@]}"; do
    test -e "$file" || warning "Critical file/directory missing: $file"
done

# Show restored version
if [[ -f ".claude/VERSION" ]]; then
    restored_version=$(cat ".claude/VERSION")
    echo "✅ Restored to version: $restored_version"
fi

# Show git status
echo ""
echo "📊 Git Status:"
git status --short || true
```

## Examples

### List Available Backups
```bash
/pm:update-rollback --list
```
Shows all available backup branches and file backups.

### Rollback to Specific Backup
```bash
/pm:update-rollback backup-20250825-143022
```
Restores from the specified backup with confirmation prompt.

### Quick Rollback
```bash
/pm:update-rollback backup-20250825-143022 --confirm
```
Rolls back immediately without confirmation prompts.

### Rollback Latest Backup
```bash
# Get latest backup name first
latest=$(git branch | grep "ccpm-backup-" | tail -1 | sed 's/.*ccpm-backup-//')
/pm:update-rollback "$latest"
```

## Error Handling

### Common Issues
- **No backup found**: Backup name doesn't exist
  - Solution: Use `--list` to see available backups
  - Check backup directory `.ccpm-backups/`

- **Partial backup**: Only git branch or files available, not both
  - Solution: Rollback will use available backup type
  - May require manual recovery for missing components

- **Corrupted backup**: Backup files damaged or incomplete
  - Solution: Try different backup
  - Check `.ccpm-backups/backup-name/backup-manifest.txt` for details

### Recovery Options
```bash
# If rollback fails
git status                    # Check current state
git log --oneline -5         # Check recent commits
git branch -a                # List all branches including backups

# Manual recovery
git reset --hard HEAD~1      # Go back one commit
git clean -fd                # Clean untracked files
```

## Safety Features

### Pre-Rollback Checks
- Validates backup existence before starting
- Warns about uncommitted changes that will be lost
- Shows exactly what will be restored

### Rollback Process
- Uses tested restore script
- Maintains backup integrity during restore
- Provides detailed progress information

### Post-Rollback Validation
- Verifies critical files are present
- Checks version information
- Shows git status for review

## Configuration

No specific configuration required. Uses existing:
- `.claude-pm.yaml` for backup settings
- Git repository for branch backups
- `.ccmp-backups/` directory for file backups

## Related Commands
- `/pm:update` - Create updates (automatically creates backups)
- `/pm:update-check` - Check if rollback is needed
- `/pm:validate` - Verify system after rollback
- `~/.claude/scripts/pm/update-restore.sh` - Low-level restore script