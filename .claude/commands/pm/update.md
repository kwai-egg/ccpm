# Command: /pm:update

## Purpose
Updates the Claude Code PM system to the latest version while preserving all project-specific data (PRDs, epics, context, and local configurations).

## Parameters
- `--dry-run`: Optional flag - Show what would be updated without making changes
- `--force`: Optional flag - Skip safety checks and force update
- `--no-backup`: Optional flag - Skip creating backup before update (not recommended)
- `--rollback`: Optional string - Roll back to specified backup name

## Prerequisites
- Git repository with clean working directory (or use `--force` to override)
- Internet connection to fetch updates
- `.claude-pm.yaml` configuration file exists
- GitHub CLI (`gh`) installed and authenticated (for some operations)

## Implementation

### Phase 1: Pre-Update Validation
```bash
# Check current directory (scripts will handle path resolution)
# Note: No longer forcing cd to git root - scripts handle their own path resolution

# Verify configuration exists
test -f "~/.claude/.claude-pm.yaml" || error "Configuration file missing. Run '/pm:init' first"

# Check for uncommitted changes (unless --force used)
if [[ "$FORCE" != true ]] && ! git diff-index --quiet HEAD --; then
    error "Uncommitted changes detected. Commit or stash changes, or use --force"
fi

# Validate dependencies
command -v git >/dev/null || error "Git not installed"
```

### Phase 2: Update Check
```bash
# Run update check to see what's available
.claude/scripts/pm/update-check.sh

# Ask user to confirm unless --dry-run
if [[ "$DRY_RUN" != true ]]; then
    echo "Continue with update? [y/N]"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || exit 0
fi
```

### Phase 3: Backup Creation
```bash
# Create backup unless --no-backup specified
if [[ "$NO_BACKUP" != true && "$DRY_RUN" != true ]]; then
    echo "🔄 Creating backup before update..."
    .claude/scripts/pm/update-backup.sh "update-$(date -u +%Y%m%d-%H%M%S)"
fi
```

### Phase 4: Update Execution
```bash
# Execute main update script
if [[ "$DRY_RUN" == true ]]; then
    .claude/scripts/pm/update.sh --dry-run
else
    .claude/scripts/pm/update.sh
fi
```

### Phase 5: Post-Update Validation
```bash
# Validate system integrity
/pm:validate

# Show update summary
echo "✅ Update completed successfully!"
echo "New version: $(cat .claude/VERSION)"
echo "Run '/pm:status' to verify everything is working"
```

### Rollback Handling
```bash
if [[ -n "$ROLLBACK" ]]; then
    echo "🔄 Rolling back to backup: $ROLLBACK"
    .claude/scripts/pm/update-restore.sh "$ROLLBACK"
    exit $?
fi
```

## Examples

### Basic Update
```bash
/pm:update
```
Checks for updates, shows what will change, creates backup, and applies updates.

### Dry Run
```bash
/pm:update --dry-run
```
Shows what would be updated without making any changes.

### Force Update
```bash
/pm:update --force
```
Updates even if there are uncommitted changes (backs up current state first).

### Update Without Backup
```bash
/pm:update --no-backup
```
Updates without creating a backup (not recommended for production use).

### Rollback to Previous Version
```bash
/pm:update --rollback backup-20250825-143022
```
Restores from the specified backup.

## Error Handling

### Pre-Update Errors
- **Not in git repository**: Must be run from project root with git initialized
- **Configuration missing**: Run `/pm:init` to set up the update system
- **Uncommitted changes**: Commit, stash, or use `--force` flag
- **No internet connection**: Cannot fetch updates from upstream

### Update Errors
- **Merge conflicts**: Update paused, manual resolution required
- **Network failures**: Retry with exponential backoff
- **Disk space issues**: Check available space before proceeding

### Recovery Options
```bash
# If update fails midway
/pm:update --rollback latest

# To check what went wrong
git status
git log --oneline -10

# To retry after fixing issues
/pm:update
```

## Safety Features

### Automatic Backups
- Git branch backup created before any changes
- File-level backup of preserved directories
- Backup manifest tracks what was backed up
- Automatic cleanup of old backups

### Validation Checks
- Pre-update: git status, dependencies, configuration
- During update: file integrity, merge conflicts
- Post-update: system validation, command availability

### Rollback Protection
- All updates are reversible via backup system
- Backup branches preserved for quick git-based recovery
- File backups available for granular restoration

## Configuration

The update behavior is controlled by `.claude-pm.yaml`:

```yaml
preserve:
  - ".claude/epics/"      # Project-specific data
  - ".claude/prds/"
  - ".claude/context/"
  
update:
  - ".claude/agents/"     # System components
  - ".claude/commands/"
  - ".claude/scripts/"

backup:
  enabled: true
  keep_backups: 5
```

## Related Commands
- `/pm:update-check` - Check for available updates without applying
- `/pm:update-status` - Show current version and update configuration
- `/pm:update-rollback` - Shortcut for rollback operations
- `/pm:validate` - Verify system integrity after update