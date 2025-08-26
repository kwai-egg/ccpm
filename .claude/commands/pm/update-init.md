# Command: /pm:update-init

## Purpose
Initialize the Claude Code PM update system for an existing project, setting up configuration and enabling automatic updates.

## Parameters
- `--upstream`: Optional string - Custom upstream URL (default: https://github.com/kwai-egg/ccpm.git)
- `--branch`: Optional string - Upstream branch to track (default: main)
- `--force`: Optional flag - Overwrite existing configuration

## Prerequisites
- Git repository initialized in project
- Claude Code PM system already present (basic installation)
- Write permissions in project directory

## Implementation

### Phase 1: Environment Validation
```bash
# Change to project root
cd "$(git rev-parse --show-toplevel)" || error "Not in a git repository"

# Check if basic Claude Code PM structure exists
test -d ".claude" || error "Claude Code PM not found. Install first: https://github.com/kwai-egg/ccpm"

# Check if already initialized (unless force)
if [[ -f ".claude-pm.yaml" && "$FORCE" != true ]]; then
    error "Update system already initialized. Use --force to reinitialize"
fi
```

### Phase 2: Configuration Creation
```bash
# Set default values
upstream_url="${upstream:-https://github.com/kwai-egg/ccpm.git}"
upstream_branch="${branch:-main}"

echo "🚀 Initializing Claude Code PM Update System"
echo ""
echo "Configuration:"
echo "  Upstream: $upstream_url"
echo "  Branch: $upstream_branch"
echo ""

# Create configuration file
cat > ".claude-pm.yaml" << EOF
---
# Claude Code PM Update Configuration
version: 1.0
upstream: $upstream_url
branch: $upstream_branch

# Files and directories to preserve during updates
preserve:
  - ".claude/epics/"
  - ".claude/prds/"
  - ".claude/context/"
  - ".claude/CLAUDE.md"
  - ".claude/**/*.local.*"
  - ".claude/settings.json"
  - ".claude/config.yaml"
  - ".gitignore"
  - "README.md"

# Files and directories to update from upstream
update:
  - ".claude/agents/"
  - ".claude/commands/"
  - ".claude/rules/"
  - ".claude/scripts/"
  - ".claude/templates/"
  - ".claude/VERSION"
  - ".claude/CHANGELOG.md"
  - "AGENTS.md"
  - "COMMANDS.md"
  - "LICENSE"

# Merge strategies
merge_strategy:
  theirs:
    - ".claude/agents/**"
    - ".claude/commands/**"
    - ".claude/rules/**"
    - ".claude/scripts/**"
    - ".claude/VERSION"
    - ".claude/CHANGELOG.md"
  ours:
    - ".claude/epics/**"
    - ".claude/prds/**"
    - ".claude/context/**"
    - ".claude/CLAUDE.md"
  merge:
    - ".gitignore"
    - "README.md"

# Backup settings
backup:
  enabled: true
  branch_prefix: "ccpm-backup-"
  keep_backups: 5
  backup_location: ".ccpm-backups/"

# Update behavior
update_behavior:
  check_uncommitted: true
  create_backup: true
  validate_after: true
  auto_cleanup: false

# Validation settings
validation:
  check_commands: true
  check_structure: true
  check_dependencies: true
  check_git_status: true
EOF
```

### Phase 3: Directory Setup
```bash
# Create backup directory
mkdir -p ".ccpm-backups"

# Add to .gitignore if not already present
if ! grep -q ".ccpm-backups" ".gitignore" 2>/dev/null; then
    echo "" >> ".gitignore"
    echo "# Claude Code PM Update System" >> ".gitignore"
    echo ".ccpm-backups/" >> ".gitignore"
fi

# Create version file if missing
if [[ ! -f ".claude/VERSION" ]]; then
    echo "1.0.0" > ".claude/VERSION"
fi

# Create changelog if missing
if [[ ! -f ".claude/CHANGELOG.md" ]]; then
    cat > ".claude/CHANGELOG.md" << 'EOF'
---
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
version: 1.0
author: Claude Code PM System
---

# Claude Code PM Changelog

## [1.0.0] - $(date -u +"%Y-%m-%d")

### Added
- Initial Claude Code PM system installation
- Project-specific implementation and customizations

### Notes
- This project has been set up with Claude Code PM update system
- Run '/pm:update-check' to check for available updates
- Run '/pm:update' to apply updates while preserving project data
EOF
fi
```

### Phase 4: Git Remote Setup
```bash
# Add upstream remote if it doesn't exist
remote_name="ccpm-upstream"
if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
    echo "📡 Adding upstream remote: $upstream_url"
    git remote add "$remote_name" "$upstream_url"
else
    existing_url=$(git remote get-url "$remote_name")
    if [[ "$existing_url" != "$upstream_url" ]]; then
        echo "📡 Updating upstream remote: $existing_url -> $upstream_url"
        git remote set-url "$remote_name" "$upstream_url"
    fi
fi

# Test upstream connectivity
echo "🔍 Testing upstream connectivity..."
if git fetch "$remote_name" "$upstream_branch" --dry-run >/dev/null 2>&1; then
    echo "  ✅ Upstream accessible"
else
    echo "  ⚠️  Upstream not accessible (network issue or authentication required)"
fi
```

### Phase 5: Initial System Check
```bash
# Run initial update check
echo ""
echo "🔍 Running initial system check..."

# Check for available updates
.claude/scripts/pm/update-check.sh || true

echo ""
echo "✅ Update system initialization complete!"
```

### Phase 6: Usage Instructions
```bash
echo ""
echo "📚 Next Steps:"
echo ""
echo "1. Check for updates:"
echo "   /pm:update-check"
echo ""
echo "2. View system status:"
echo "   /pm:update-status"
echo ""
echo "3. Apply updates (when available):"
echo "   /pm:update"
echo ""
echo "4. For help with update commands:"
echo "   /pm:help | grep update"
echo ""
echo "📝 Configuration saved to: .claude-pm.yaml"
echo "💾 Backups will be stored in: .ccpm-backups/"
echo ""
echo "🔧 To customize settings, edit .claude-pm.yaml"
```

## Examples

### Basic Initialization
```bash
/pm:update-init
```
Sets up update system with default GitHub upstream.

### Custom Upstream
```bash
/pm:update-init --upstream https://github.com/myorg/my-ccpm-fork.git
```
Uses custom upstream repository.

### Different Branch
```bash
/pm:update-init --branch develop --upstream https://github.com/kwai-egg/ccpm.git
```
Tracks develop branch instead of main.

### Force Reinitialize
```bash
/pm:update-init --force
```
Overwrites existing configuration with fresh setup.

## Error Handling

### Common Issues
- **Not in git repo**: Must run from git repository root
- **Missing .claude/**: Claude Code PM not installed
- **Already initialized**: Use --force to reinitialize
- **Network issues**: Upstream may not be accessible

### Recovery
```bash
# If initialization fails partway through
rm -f ".claude-pm.yaml"    # Remove partial config
/pm:update-init --force    # Try again

# If upstream is wrong
/pm:update-init --upstream https://correct-url.git --force
```

## Configuration File Structure

The generated `.claude-pm.yaml` includes:

- **Upstream settings**: Repository and branch to track
- **Preserve patterns**: Files/directories to keep unchanged
- **Update patterns**: Files/directories to update from upstream
- **Merge strategies**: How to handle different file types
- **Backup settings**: Backup behavior and retention
- **Validation rules**: Post-update checks to perform

## Related Commands
- `/pm:update-check` - Check for available updates
- `/pm:update` - Apply system updates
- `/pm:update-status` - View system status
- `/pm:validate` - Verify system integrity