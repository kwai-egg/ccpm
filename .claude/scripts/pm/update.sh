#!/bin/bash
# Script: update.sh (rewritten for non-git .claude folders)
# Purpose: Main Claude Code PM update implementation using GitHub API
# Usage: ./update.sh [--dry-run] [--force] [--no-backup]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source path resolver for flexible path handling
source "$SCRIPT_DIR/path-resolver.sh"

# Use resolved paths
PROJECT_ROOT="$PROJECT_ROOT"  # From path-resolver.sh
CLAUDE_DIR="$CLAUDE_DIR"      # From path-resolver.sh
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

# Source GitHub utilities
source "$SCRIPT_DIR/github-utils.sh"

# Validate environment
function validate_environment() {
    # Check if .claude directory exists (either local or global)
    if [[ ! -d "$CLAUDE_DIR" ]]; then
        error_exit "Claude Code PM not found (.claude directory missing at $CLAUDE_DIR)"
    fi

    # Check for uncommitted git changes if in a git repo (optional warning)
    if git rev-parse --git-dir >/dev/null 2>&1; then
        if [[ "$FORCE" != true ]] && ! git diff-index --quiet HEAD --; then
            warning "You have uncommitted git changes. Consider committing them first."
            if [[ "$DRY_RUN" != true ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Update cancelled"
                    exit 0
                fi
            fi
        fi
    fi

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE. Run '/pm:update-init' first"
    fi
}

# Parse configuration
function read_config() {
    if command -v yq >/dev/null 2>&1; then
        # Use yq if available
        UPSTREAM_URL=$(yq eval '.upstream' "$CONFIG_FILE")
        UPSTREAM_BRANCH=$(yq eval '.branch // "main"' "$CONFIG_FILE")
    else
        # Fallback parsing
        UPSTREAM_URL=$(grep -E "^upstream:" "$CONFIG_FILE" | sed 's/upstream: *//' | tr -d '"' | tr -d "'")
        UPSTREAM_BRANCH=$(grep -E "^branch:" "$CONFIG_FILE" | sed 's/branch: *//' | tr -d '"' | tr -d "'" || echo "main")
        UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-main}
    fi
    
    if [[ -z "$UPSTREAM_URL" ]]; then
        error_exit "No upstream URL configured in $CONFIG_FILE"
    fi
    
    info "Upstream: $UPSTREAM_URL (branch: $UPSTREAM_BRANCH)"
}

# Check if update is needed
function check_update_needed() {
    # Initialize GitHub utilities
    init_github_utils "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
    
    # Get version information
    if [[ -f "$VERSION_FILE" ]]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
    else
        CURRENT_VERSION="unknown"
    fi
    
    # Get upstream version
    UPSTREAM_VERSION=$(get_remote_version "$UPSTREAM_BRANCH")
    if [[ $? -ne 0 || -z "$UPSTREAM_VERSION" ]]; then
        error_exit "Could not fetch upstream version"
    fi
    
    info "Current version: $CURRENT_VERSION"
    info "Upstream version: $UPSTREAM_VERSION"
    
    # Check if versions are the same and no file differences
    if [[ "$CURRENT_VERSION" == "$UPSTREAM_VERSION" && "$CURRENT_VERSION" != "unknown" ]]; then
        # Still check for file differences in case of same version but different files
        local files_need_update=false
        
        # Get list of remote files to check
        local remote_files
        remote_files=$(fetch_github_tree_recursive ".claude" "$UPSTREAM_BRANCH")
        if [[ $? -eq 0 ]]; then
            while IFS= read -r remote_file; do
                [[ -z "$remote_file" ]] && continue
                
                if should_update_file "$remote_file"; then
                    local remote_content
                    remote_content=$(fetch_github_file "$remote_file" "$UPSTREAM_BRANCH")
                    if [[ $? -eq 0 ]]; then
                        if ! compare_file_checksums "$remote_file" "$remote_content"; then
                            files_need_update=true
                            break
                        fi
                    fi
                fi
            done <<< "$remote_files"
        fi
        
        if [[ "$files_need_update" == false ]]; then
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

# Apply file updates from upstream
function apply_file_updates() {
    header "📦 Applying file updates from upstream..."
    
    # Get list of remote files
    local remote_files
    remote_files=$(fetch_github_tree_recursive ".claude" "$UPSTREAM_BRANCH")
    if [[ $? -ne 0 ]]; then
        error_exit "Could not fetch remote file list"
    fi
    
    local update_count=0
    local preserve_count=0
    local error_count=0
    
    # Create temporary backup directory for this update
    local temp_backup_dir="$CLAUDE_DIR/.ccpm-backups/temp-$(date -u +%Y%m%d-%H%M%S)"
    mkdir -p "$temp_backup_dir"
    
    # Process each file
    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        
        local local_file="$remote_file"
        local action="skip"
        
        # Determine what to do with this file
        if should_preserve_file "$remote_file"; then
            action="preserve"
            preserve_count=$((preserve_count + 1))
        elif should_update_file "$remote_file"; then
            # Check if file actually needs updating
            local remote_content
            remote_content=$(fetch_github_file "$remote_file" "$UPSTREAM_BRANCH")
            if [[ $? -eq 0 ]]; then
                if [[ ! -f "$local_file" ]] || ! compare_file_checksums "$local_file" "$remote_content"; then
                    action="update"
                else
                    action="unchanged"
                fi
            else
                action="error"
                error_count=$((error_count + 1))
            fi
        fi
        
        # Perform action
        case "$action" in
            "update")
                info "📝 Updating: $local_file"
                if [[ "$DRY_RUN" != true ]]; then
                    # Backup existing file
                    if [[ -f "$local_file" ]]; then
                        mkdir -p "$temp_backup_dir/$(dirname "$local_file")"
                        cp "$local_file" "$temp_backup_dir/$local_file" 2>/dev/null || true
                    fi
                    
                    # Ensure directory exists
                    mkdir -p "$(dirname "$local_file")"
                    
                    # Write new content
                    echo "$remote_content" > "$local_file"
                    update_count=$((update_count + 1))
                else
                    dry_run_info "Would update $local_file"
                fi
                ;;
            "preserve")
                info "🔒 Preserving: $local_file"
                ;;
            "unchanged")
                info "➡️  Unchanged: $local_file"
                ;;
            "error")
                warning "❌ Error fetching: $local_file"
                ;;
        esac
    done <<< "$remote_files"
    
    info "📊 Update summary: $update_count updated, $preserve_count preserved, $error_count errors"
    
    if [[ $error_count -gt 0 ]]; then
        warning "Some files could not be updated due to errors"
    fi
}

# Update root-level files (README, LICENSE, etc.)
function update_root_files() {
    header "📄 Checking root-level files..."
    
    # List of root files that might need updating
    local root_files=("README.md" "LICENSE" "AGENTS.md" "COMMANDS.md" "screenshot.webp")
    
    for file in "${root_files[@]}"; do
        if should_update_file "$file"; then
            local remote_content
            remote_content=$(fetch_github_file "$file" "$UPSTREAM_BRANCH")
            if [[ $? -eq 0 ]]; then
                if [[ ! -f "$file" ]] || ! compare_file_checksums "$file" "$remote_content"; then
                    info "📝 Updating root file: $file"
                    if [[ "$DRY_RUN" != true ]]; then
                        echo "$remote_content" > "$file"
                    else
                        dry_run_info "Would update $file"
                    fi
                fi
            fi
        fi
    done
}

# Sync .gitignore with configuration (disabled for standalone .claude operation)
function sync_gitignore() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_info "Skipping .gitignore sync (standalone .claude mode)"
        return
    fi
    
    info "Skipping .gitignore sync (standalone .claude mode)..."
    # Note: When running from .claude directory, we don't modify root .gitignore
}

# Validate update
function validate_update() {
    if [[ "$DRY_RUN" == true ]]; then
        dry_run_info "Would validate update integrity"
        return
    fi
    
    info "Validating update..."
    
    # Check critical files exist
    local critical_files=("$CLAUDE_DIR/VERSION" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/agents")
    for file in "${critical_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            error_exit "Critical file/directory missing after update: $file"
        fi
    done
    
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
        local restore_script="$(resolve_script 'pm/update-restore.sh' || echo '$CLAUDE_DIR/scripts/pm/update-restore.sh')"
        info "To rollback: $restore_script $BACKUP_NAME"
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
    
    validate_environment
    read_config
    check_update_needed
    create_backup
    apply_file_updates
    update_root_files
    validate_update
    show_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi