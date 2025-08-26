# Command: /pm:update-status

## Purpose
Display comprehensive status information about the Claude Code PM system, including version, configuration, and update history.

## Parameters
- `--verbose`: Optional flag - Show detailed system information
- `--health`: Optional flag - Include system health checks

## Prerequisites
- Claude Code PM system initialized in project
- Git repository (for some status information)

## Implementation

### Phase 1: Basic System Information
```bash
# Change to project root
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || cd "."

echo "📊 Claude Code PM System Status"
echo "================================"
echo ""

# Current version
if [[ -f ".claude/VERSION" ]]; then
    current_version=$(cat ".claude/VERSION")
    echo "🔖 Current Version: $current_version"
else
    echo "⚠️  Version file not found"
    current_version="unknown"
fi

# Installation date (from git history)
if git log --oneline --reverse | head -1 >/dev/null 2>&1; then
    install_date=$(git log --reverse --format="%ci" -- .claude/ | head -1 | cut -d' ' -f1)
    echo "📅 Installed: $install_date"
fi
```

### Phase 2: Configuration Status
```bash
echo ""
echo "⚙️  Configuration:"

# Check configuration file
if [[ -f ".claude-pm.yaml" ]]; then
    echo "  ✅ Configuration file: .claude-pm.yaml"
    
    # Parse upstream information
    if command -v yq >/dev/null 2>&1; then
        upstream_url=$(yq eval '.upstream' ".claude-pm.yaml" 2>/dev/null || echo "not configured")
        upstream_branch=$(yq eval '.branch // "main"' ".claude-pm.yaml" 2>/dev/null)
    else
        upstream_url=$(grep "upstream:" ".claude-pm.yaml" | cut -d'"' -f2 2>/dev/null || echo "not configured")
        upstream_branch=$(grep "branch:" ".claude-pm.yaml" | cut -d'"' -f2 2>/dev/null || echo "main")
    fi
    
    echo "  📡 Upstream: $upstream_url"
    echo "  🌿 Branch: $upstream_branch"
else
    echo "  ❌ Configuration file missing"
fi

# Check for backup configuration
if [[ -d ".ccmp-backups" ]]; then
    backup_count=$(ls -1 ".ccmp-backups" | wc -l | tr -d ' ')
    echo "  💾 Backups available: $backup_count"
else
    echo "  💾 Backup directory: not found"
fi
```

### Phase 3: Component Status
```bash
echo ""
echo "🔧 System Components:"

# Core directories
components=(
    ".claude/agents:AI Agents"
    ".claude/commands:Commands"
    ".claude/context:Context System"
    ".claude/rules:Rules"
    "~/.claude/scripts:Scripts"
)

for component in "${components[@]}"; do
    dir="${component%:*}"
    name="${component#*:}"
    
    if [[ -d "$dir" ]]; then
        file_count=$(find "$dir" -type f | wc -l | tr -d ' ')
        echo "  ✅ $name: $file_count files"
    else
        echo "  ❌ $name: missing"
    fi
done
```

### Phase 4: Update History (if verbose)
```bash
if [[ "$VERBOSE" == true ]]; then
    echo ""
    echo "📚 Update History:"
    
    # Git backup branches (recent updates)
    backup_branches=$(git branch | grep "ccpm-backup-" | tail -5 || true)
    if [[ -n "$backup_branches" ]]; then
        echo "  Recent backups:"
        echo "$backup_branches" | sed 's/^[* ]*/    /'
    else
        echo "  No backup branches found"
    fi
    
    # Recent commits affecting .claude/
    echo ""
    echo "  Recent changes:"
    git log --oneline --format="    %ci %s" -- .claude/ | head -5 2>/dev/null || echo "    No commit history found"
fi
```

### Phase 5: Health Checks (if requested)
```bash
if [[ "$HEALTH" == true ]]; then
    echo ""
    echo "🏥 System Health:"
    
    # Check critical files
    critical_files=(
        ".claude/VERSION:Version file"
        ".claude/commands/pm:PM commands"
        ".claude/agents:Agent definitions"
        "~/.claude/scripts/pm:PM scripts"
    )
    
    for check in "${critical_files[@]}"; do
        file="${check%:*}"
        desc="${check#*:}"
        
        if [[ -e "$file" ]]; then
            echo "  ✅ $desc"
        else
            echo "  ❌ $desc (missing)"
        fi
    done
    
    # Check git status
    if git rev-parse --git-dir >/dev/null 2>&1; then
        if git diff-index --quiet HEAD --; then
            echo "  ✅ Git working directory clean"
        else
            echo "  ⚠️  Git working directory has changes"
        fi
    else
        echo "  ❌ Not in a git repository"
    fi
    
    # Check dependencies
    deps=(
        "git:Git version control"
        "gh:GitHub CLI (optional)"
    )
    
    for dep in "${deps[@]}"; do
        cmd="${dep%:*}"
        desc="${dep#*:}"
        
        if command -v "$cmd" >/dev/null; then
            version=$($cmd --version 2>/dev/null | head -1 || echo "unknown")
            echo "  ✅ $desc ($version)"
        else
            echo "  ⚠️  $desc (not installed)"
        fi
    done
fi
```

### Phase 6: Recommendations
```bash
echo ""
echo "💡 Recommendations:"

# Check if update check is needed
last_check_file=".claude/.last-update-check"
if [[ -f "$last_check_file" ]]; then
    last_check=$(cat "$last_check_file")
    days_ago=$((($(date +%s) - last_check) / 86400))
    if [[ $days_ago -gt 7 ]]; then
        echo "  🔄 Run '/pm:update-check' (last checked $days_ago days ago)"
    fi
else
    echo "  🔄 Run '/pm:update-check' to check for updates"
fi

# Configuration recommendations
if [[ ! -f ".claude-pm.yaml" ]]; then
    echo "  ⚙️  Run '/pm:init' to set up update system"
fi

if [[ ! -d ".ccpm-backups" ]]; then
    echo "  💾 Run '/pm:update' to create backup system"
fi

# Validation recommendation
echo "  ✅ Run '/pm:validate' to verify system integrity"
```

## Examples

### Basic Status
```bash
/pm:update-status
```
Shows version, configuration, and component status.

### Detailed Status
```bash
/pm:update-status --verbose
```
Includes update history and recent changes.

### Health Check
```bash
/pm:update-status --health
```
Includes system health validation and dependency checks.

### Combined
```bash
/pm:update-status --verbose --health
```
Complete system status with all available information.

## Output Format

### Basic Output
```
📊 Claude Code PM System Status
================================

🔖 Current Version: 1.0.0
📅 Installed: 2025-08-25

⚙️  Configuration:
  ✅ Configuration file: .claude-pm.yaml
  📡 Upstream: https://github.com/kwai-egg/ccpm.git
  🌿 Branch: main
  💾 Backups available: 3

🔧 System Components:
  ✅ AI Agents: 4 files
  ✅ Commands: 25 files
  ✅ Context System: 10 files
  ✅ Rules: 8 files
  ✅ Scripts: 12 files

💡 Recommendations:
  ✅ Run '/pm:validate' to verify system integrity
```

## Exit Codes

- **0**: System status retrieved successfully
- **1**: System has issues that need attention
- **2**: Critical system components missing

## Use Cases

### Daily Development Check
```bash
/pm:update-status --health
```
Quick health check before starting development work.

### System Diagnostics
```bash
/pm:update-status --verbose --health
```
Complete diagnostics when troubleshooting issues.

### Automation Integration
```bash
# Check if system needs attention
if ! /pm:update-status >/dev/null 2>&1; then
    echo "System needs attention"
    /pm:update-status --health
fi
```

## Related Commands
- `/pm:validate` - Run comprehensive system validation
- `/pm:update-check` - Check for available updates
- `/pm:update` - Apply system updates
- `/pm:init` - Initialize update system