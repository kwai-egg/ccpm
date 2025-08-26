# Command: /pm:gitignore-sync

## Purpose
Synchronizes the project's `.gitignore` file with the configuration in `.claude-pm.yaml`, ensuring that files under "update" sections are ignored while files under "preserve" sections are tracked.

## Parameters
None

## Prerequisites
- Project must have `.claude-pm.yaml` configuration file
- Project must be initialized with Claude Code PM (`/pm:init`)
- Write access to project root directory

## Implementation

### Overview
This command parses the `.claude-pm.yaml` file and automatically manages a dedicated section in the project's `.gitignore` file. It ensures that:
- All paths listed under the "update" section in `.claude-pm.yaml` are added to `.gitignore` (should not be committed)
- All paths listed under the "preserve" section are NOT in `.gitignore` (should be committed)
- System files like `.ccpm-backups/` and `.claude/.last-update-check` are always ignored
- Existing non-Claude entries in `.gitignore` are preserved

### Execution Steps

1. **Validate Environment**
   ```bash
   # Check for required files
   test -f .claude-pm.yaml || error "Configuration file .claude-pm.yaml not found"
   test -d .claude || error "Claude Code PM not initialized"
   ```

2. **Parse Configuration**
   ```bash
   # Extract paths from YAML sections
   extract_yaml_paths "update"    # Files that should be ignored
   extract_yaml_paths "preserve"  # Files that should be tracked
   ```

3. **Generate Managed Section**
   ```bash
   # Create managed gitignore section with clear markers
   echo "# === Claude Code PM (auto-managed) ==="
   echo "# DO NOT EDIT THIS SECTION MANUALLY"
   echo "# Managed by .claude/scripts/pm/gitignore-sync.sh"
   
   # Add all "update" paths
   for path in $UPDATE_PATHS; do
       echo "$path"
   done
   
   # Add system files
   echo ".ccpm-backups/"
   echo ".claude/.last-update-check"
   echo "# === End Claude Code PM ==="
   ```

4. **Update .gitignore File**
   ```bash
   # Preserve existing content before and after managed section
   # Replace only the managed section between markers
   # Create .gitignore if it doesn't exist
   ```

5. **Report Results**
   ```bash
   # Show what was added/removed
   echo "✅ .gitignore synchronized successfully"
   echo "📝 Added to .gitignore:"
   for path in $UPDATE_PATHS; do
       echo "  - $path"
   done
   ```

### Script Execution
```bash
# Execute the gitignore sync script
\.claude/scripts/pm/gitignore-sync.sh
```

## Examples

### Basic Usage
```bash
/pm:gitignore-sync
```

### Expected Output
```
🔄 Synchronizing .gitignore with .claude-pm.yaml
✅ .gitignore synchronized successfully
📝 Added to .gitignore:
  - .claude/agents/
  - .claude/commands/
  - .claude/rules/
  - .claude/scripts/
  - .claude/templates/
  - .claude/VERSION
  - .claude/CHANGELOG.md
```

### Resulting .gitignore Structure
```gitignore
# Existing project entries
.DS_Store
node_modules/
dist/

# === Claude Code PM (auto-managed) ===
# DO NOT EDIT THIS SECTION MANUALLY  
# Managed by .claude/scripts/pm/gitignore-sync.sh
.claude/agents/
.claude/commands/
.claude/rules/
.claude/scripts/
.claude/templates/
.claude/VERSION
.claude/CHANGELOG.md
.ccpm-backups/
.claude/.last-update-check
# === End Claude Code PM ===

# Other custom entries
.env.local
```

## Error Handling

### Configuration File Missing
```
❌ Error: Configuration file not found: .claude-pm.yaml
💡 Try: Run '/pm:update-init' to create configuration
```

### Permission Issues
```
❌ Error: Cannot write to .gitignore file
💡 Try: Check file permissions with 'ls -la .gitignore'
💡 Or: Fix permissions with 'chmod 644 .gitignore'
```

### Invalid YAML Configuration
```
❌ Error: Cannot parse .claude-pm.yaml configuration
💡 Try: Check YAML syntax with a YAML validator
💡 Or: Restore from backup: '\.claude/scripts/pm/update-restore.sh <backup-name>'
```

### Script Not Found
```
❌ Error: gitignore-sync.sh script not found or not executable
💡 Try: Run '/pm:update' to update system scripts
💡 Or: Check script permissions: 'ls -la .claude/scripts/pm/gitignore-sync.sh'
```

## Integration

### Automatic Execution
This command is automatically executed during:
- System updates (`/pm:update`)
- Initial setup (`/pm:init`)
- Configuration changes

### Manual Execution
Run manually when:
- Modifying `.claude-pm.yaml` configuration
- Troubleshooting gitignore issues
- Adding custom project-specific ignore rules

### Validation
The command validates:
- YAML configuration syntax
- File system permissions
- Managed section integrity
- No conflicts with existing entries

## Related Commands
- `/pm:update` - Includes automatic gitignore sync
- `/pm:update-init` - Creates initial configuration
- `/pm:validate` - Validates system integrity including gitignore
- `/pm:status` - Shows current sync status

## Notes
- The managed section uses clear start/end markers to prevent conflicts
- Existing .gitignore entries outside the managed section are never modified
- The sync is idempotent - running multiple times produces the same result
- All changes are logged for transparency and debugging