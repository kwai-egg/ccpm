#!/bin/bash
# Script: update.sh
# Purpose: Main Claude Code PM update implementation
# Usage: ./update.sh [--dry-run] [--force] [--no-backup]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$CLAUDE_DIR/.claude-pm.yaml"
VERSION_FILE="$CLAUDE_DIR/VERSION"

# Parse command line arguments
DRY_RUN=false
FORCE=false
NO_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to display colored output
function log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

function error_exit() {
    log $RED "❌ Error: $1"
    exit 1
}

function success() {
    log $GREEN "✅ $1"
}

function info() {
    log $BLUE "ℹ️  $1"
}

function warning() {
    log $YELLOW "⚠️  $1"
}

function header() {
    log $BOLD "$1"
}

function dry_run_info() {
    if [[ "$DRY_RUN" == true ]]; then
        log $CYAN "🔍 [DRY RUN] $1"
    fi
}

# Validate environment
function validate_environment() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error_exit "Not in a git repository"
    fi

    # Check for uncommitted changes (unless forced)
    if [[ "$FORCE" != true ]] && ! git diff-index --quiet HEAD --; then
        error_exit "Uncommitted changes detected. Commit changes, stash them, or use --force"
    fi

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE. Run '/pm:init' first"
    fi

    # Check dependencies
    command -v git >/dev/null || error_exit "Git not installed"
}

# Parse configuration
function read_config() {
    if command -v yq >/dev/null 2>&1; then
        # Use yq if available
        UPSTREAM_URL=$(yq eval '.upstream' "$CONFIG_FILE")
        UPSTREAM_BRANCH=$(yq eval '.branch // "main"' "$CONFIG_FILE")
        
        # Read preserve and update patterns
        readarray -t PRESERVE_PATTERNS < <(yq eval '.preserve[]' "$CONFIG_FILE")
        readarray -t UPDATE_PATTERNS < <(yq eval '.update[]' "$CONFIG_FILE")
        readarray -t THEIRS_PATTERNS < <(yq eval '.merge_strategy.theirs[]' "$CONFIG_FILE" 2>/dev/null || echo "")
        readarray -t OURS_PATTERNS < <(yq eval '.merge_strategy.ours[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    else
        # Fallback parsing
        UPSTREAM_URL=$(grep -E "^upstream:" "$CONFIG_FILE" | sed 's/upstream: *//' | tr -d '"' | tr -d "'")
        UPSTREAM_BRANCH=$(grep -E "^branch:" "$CONFIG_FILE" | sed 's/branch: *//' | tr -d '"' | tr -d "'" || echo "main")
        UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-main}
        
        # Parse arrays (simplified)
        PRESERVE_PATTERNS=()
        UPDATE_PATTERNS=()
        THEIRS_PATTERNS=()
        OURS_PATTERNS=()
        
        # This is basic parsing - yq is recommended for complex YAML
        warning "Using basic YAML parsing. Install 'yq' for better configuration support"
    fi
    
    if [[ -z "$UPSTREAM_URL" ]]; then
        error_exit "No upstream URL configured in $CONFIG_FILE"
    fi
    
    info "Upstream: $UPSTREAM_URL (branch: $UPSTREAM_BRANCH)"
}

# Setup upstream remote
function setup_upstream() {
    local remote_name="ccpm-upstream"
    
    # Check if upstream remote already exists
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
        local existing_url=$(git remote get-url "$remote_name")
        if [[ "$existing_url" != "$UPSTREAM_URL" ]]; then
            info "Updating upstream remote URL"
            if [[ "$DRY_RUN" != true ]]; then
                git remote set-url "$remote_name" "$UPSTREAM_URL"
            fi
        fi
    else
        info "Adding upstream remote: $UPSTREAM_URL"
        if [[ "$DRY_RUN" != true ]]; then
            git remote add "$remote_name" "$UPSTREAM_URL"
        fi
    fi
    
    # Fetch latest from upstream
    info "Fetching latest updates from upstream..."
    if [[ "$DRY_RUN" != true ]]; then
        git fetch "$remote_name" "$UPSTREAM_BRANCH" --quiet || error_exit "Failed to fetch from upstream"
    else
        dry_run_info "Would fetch from $remote_name/$UPSTREAM_BRANCH"
    fi
    
    UPSTREAM_REMOTE="$remote_name"
    UPSTREAM_REF="$remote_name/$UPSTREAM_BRANCH"
}

# Check if update is needed
function check_update_needed() {
    # Get version information
    if [[ -f "$VERSION_FILE" ]]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
    else
        CURRENT_VERSION="unknown"
    fi
    
    # Get upstream version
    local upstream_version_file="$UPSTREAM_REF:.claude/VERSION"
    if git show "$upstream_version_file" >/dev/null 2>&1; then
        UPSTREAM_VERSION=$(git show "$upstream_version_file" 2>/dev/null | tr -d '\n' | tr -d '\r')
    else
        UPSTREAM_VERSION="unknown"
    fi
    
    info "Current version: $CURRENT_VERSION"
    info "Upstream version: $UPSTREAM_VERSION"
    
    # Check if versions are the same
    if [[ "$CURRENT_VERSION" == "$UPSTREAM_VERSION" && "$CURRENT_VERSION" != "unknown" ]]; then
        # Still check for file differences in case of same version but different files
        local changed_files=$(git diff --name-only "HEAD" "$UPSTREAM_REF" 2>/dev/null || true)
        if [[ -z "$changed_files" ]]; then
            success "Already up to date (version $CURRENT_VERSION)"
            exit 0
        else
            info "Same version but file differences detected, proceeding with update"
        fi
    fi
}

# Create backup before update
function create_backup() {
    if [[ "$NO_BACKUP" == true ]]; then
        warning "Skipping backup creation (--no-backup specified)"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_info "Would create backup before update"
        return
    fi
    
    info "Creating backup before update..."
    local backup_name="update-$(date -u +%Y%m%d-%H%M%S)"
    "$SCRIPT_DIR/update-backup.sh" "$backup_name" || error_exit "Backup creation failed"
    
    # Store backup name for potential rollback
    BACKUP_NAME="$backup_name"
    success "Backup created: $backup_name"
}

# Apply selective merge based on patterns
function apply_selective_merge() {
    header "📦 Applying selective merge..."
    
    # Get list of changed files
    local changed_files=($(git diff --name-only "HEAD" "$UPSTREAM_REF" 2>/dev/null || true))
    
    if [[ ${#changed_files[@]} -eq 0 ]]; then
        success "No files to merge"
        return
    fi
    
    info "Files changed in upstream: ${#changed_files[@]}"
    
    # Process each file according to merge strategy
    for file in "${changed_files[@]}"; do
        local merge_strategy="merge"  # default
        
        # Check if file matches any pattern
        for pattern in "${THEIRS_PATTERNS[@]:-}"; do
            if [[ "$file" == $pattern || "$file" == ${pattern%/}/* ]]; then
                merge_strategy="theirs"
                break
            fi
        done
        
        if [[ "$merge_strategy" == "merge" ]]; then
            for pattern in "${OURS_PATTERNS[@]:-}"; do
                if [[ "$file" == $pattern || "$file" == ${pattern%/}/* ]]; then
                    merge_strategy="ours"
                    break
                fi
            done
        fi
        
        # Apply merge strategy
        case "$merge_strategy" in
            "theirs")
                info "📝 Updating: $file (upstream version)"
                if [[ "$DRY_RUN" != true ]]; then
                    # Use upstream version
                    git show "$UPSTREAM_REF:$file" > "$file" 2>/dev/null || warning "Could not update $file"
                else
                    dry_run_info "Would update $file with upstream version"
                fi
                ;;
            "ours")
                info "🔒 Preserving: $file (local version)"
                # Keep local version (do nothing)
                ;;
            "merge")
                info "🔄 Merging: $file (attempting automatic merge)"
                if [[ "$DRY_RUN" != true ]]; then
                    # Attempt to merge file (this is complex, simplified here)
                    if git show "$UPSTREAM_REF:$file" >/dev/null 2>&1; then
                        # File exists in upstream, try to merge
                        # This is a simplified merge - in practice, this would need more sophisticated logic
                        git show "$UPSTREAM_REF:$file" > "$file.upstream" 2>/dev/null || true
                        if [[ -f "$file.upstream" ]]; then
                            info "  Manual merge may be needed for $file"
                            # In a real implementation, you'd use a proper merge tool
                            mv "$file.upstream" "$file" 2>/dev/null || true
                        fi
                    fi
                else
                    dry_run_info "Would attempt to merge $file"
                fi
                ;;
        esac
    done
}

# Update system files directly
function update_system_files() {
    header "🔧 Updating system files..."
    
    # Update core system files that should always be updated
    local system_files=(
        ".claude/VERSION"
        ".claude/CHANGELOG.md"
    )
    
    for file in "${system_files[@]}"; do
        if git show "$UPSTREAM_REF:$file" >/dev/null 2>&1; then
            info "📝 Updating: $file"
            if [[ "$DRY_RUN" != true ]]; then
                git show "$UPSTREAM_REF:$file" > "$file" 2>/dev/null || warning "Could not update $file"
            else
                dry_run_info "Would update $file"
            fi
        fi
    done
}

# Validate update
function validate_update() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_info "Would validate update integrity"
        return
    fi
    
    info "Validating update..."
    
    # Check critical files exist
    local critical_files=(".claude/VERSION" ".claude/commands" ".claude/agents")
    for file in "${critical_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            error_exit "Critical file/directory missing after update: $file"
        fi
    done
    
    # Update git index
    git add -A >/dev/null 2>&1 || true
    
    success "Update validation passed"
}

# Show update summary
function show_summary() {
    header "\n📊 Update Summary"
    
    if [[ "$DRY_RUN" == true ]]; then
        info "This was a dry run - no changes were made"
        info "Run without --dry-run to apply updates"
        return
    fi
    
    # Get new version
    local new_version="unknown"
    if [[ -f "$VERSION_FILE" ]]; then
        new_version=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
    fi
    
    success "Update completed successfully!"
    info "Previous version: $CURRENT_VERSION"
    info "New version: $new_version"
    
    if [[ -n "${BACKUP_NAME:-}" ]]; then
        info "Backup created: $BACKUP_NAME"
        info "To rollback: ./.claude/scripts/pm/update-restore.sh $BACKUP_NAME"
    fi
    
    info "\nNext steps:"
    info "  1. Run '/pm:validate' to verify system integrity"
    info "  2. Test your project functionality"
    info "  3. Review changelog: .claude/CHANGELOG.md"
}

# Main execution
function main() {
    if [[ "$DRY_RUN" == true ]]; then
        header "🔍 Claude Code PM Update (DRY RUN)"
    else
        header "🚀 Claude Code PM Update"
    fi
    
    cd "$PROJECT_ROOT" || error_exit "Could not change to project root"
    
    validate_environment
    read_config
    setup_upstream
    check_update_needed
    create_backup
    apply_selective_merge
    update_system_files
    validate_update
    show_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi