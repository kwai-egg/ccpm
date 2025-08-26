#!/bin/bash
# Script: update-restore.sh (rewritten for non-git .claude folders)
# Purpose: Restore from Claude Code PM backup (file-based)
# Usage: ./update-restore.sh [backup-name]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$CLAUDE_DIR/.ccpm-backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

function confirm() {
    local message=$1
    log $YELLOW "$message"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled"
        exit 0
    fi
}

# Show usage if no backup name provided
function show_usage() {
    echo "Usage: $0 [backup-name]"
    echo ""
    echo "Available backups:"
    
    # List backup directories
    echo ""
    echo "File backups:"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -1t "$BACKUP_DIR" 2>/dev/null | grep "^backup-" | head -10 | sed 's/^/  /' || echo "  (no backup directories found)"
    else
        echo "  (no backup directory found)"
    fi
    
    # Show git tags if in git repo
    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo ""
        echo "Git tags:"
        git tag -l "ccmp-backup-*" 2>/dev/null | tail -10 | sed 's/^/  /' || echo "  (no backup tags found)"
    fi
    
    exit 1
}

# Validate environment
function validate_environment() {
    # Check if .claude directory exists
    if [[ ! -d "$PROJECT_ROOT/.claude" ]]; then
        error_exit "Claude Code PM not found (.claude directory missing)"
    fi

    # Warn about uncommitted git changes if in git repo
    if git rev-parse --git-dir >/dev/null 2>&1; then
        if ! git diff-index --quiet HEAD --; then
            confirm "⚠️  You have uncommitted git changes. Restoring will not affect git, but you may want to commit first."
        fi
    fi
}

# Find backup by name
function find_backup() {
    local backup_name="$1"
    
    # Check for file backup
    BACKUP_PATH="$BACKUP_DIR/$backup_name"
    if [[ -d "$BACKUP_PATH" ]]; then
        BACKUP_FILES_EXIST=true
        info "Found backup files: $BACKUP_PATH"
        
        # Check for backup info
        if [[ -f "$BACKUP_PATH/backup-info.json" ]]; then
            local backup_date=$(grep '"created"' "$BACKUP_PATH/backup-info.json" 2>/dev/null | cut -d'"' -f4 || echo "unknown")
            local claude_version=$(grep '"claude_version"' "$BACKUP_PATH/backup-info.json" 2>/dev/null | cut -d'"' -f4 || echo "unknown")
            info "Backup created: $backup_date"
            info "Claude version: $claude_version"
        fi
    else
        BACKUP_FILES_EXIST=false
        warning "Backup files not found: $BACKUP_PATH"
    fi
    
    # Check for git tag
    GIT_TAG_EXISTS=false
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local tag_name="ccpm-backup-$backup_name"
        if git tag -l "$tag_name" | grep -q "^$tag_name$"; then
            GIT_TAG_EXISTS=true
            info "Found git tag: $tag_name"
        fi
    fi
    
    # Must have file backup (git tag is optional)
    if [[ "$BACKUP_FILES_EXIST" == false ]]; then
        error_exit "No backup found with name: $backup_name"
    fi
}

# Restore preserved files
function restore_preserved_files() {
    if [[ "$BACKUP_FILES_EXIST" == true ]]; then
        info "Restoring preserved files from: $BACKUP_PATH"
        
        # Check if backup manifest exists
        local manifest="$BACKUP_PATH/backup-manifest.txt"
        if [[ -f "$manifest" ]]; then
            info "Using backup manifest for restore"
            
            # Count files to restore
            local file_count=$(grep -v "^#" "$manifest" | grep -v "^$" | wc -l | tr -d ' ')
            info "Restoring $file_count items from backup"
            
            # Restore files listed in manifest
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                local file="$line"
                local backup_file="$BACKUP_PATH/$file"
                
                # Handle special cases
                if [[ "$file" == ".claude/ (complete)" ]]; then
                    # Restore complete .claude directory
                    if [[ -d "$BACKUP_PATH/.claude-complete" ]]; then
                        info "Restoring complete .claude directory"
                        rm -rf .claude/* 2>/dev/null || true
                        cp -r "$BACKUP_PATH/.claude-complete"/* .claude/ 2>/dev/null || true
                    fi
                    continue
                fi
                
                if [[ -f "$backup_file" ]]; then
                    info "Restoring file: $file"
                    mkdir -p "$(dirname "$file")"
                    cp "$backup_file" "$file"
                elif [[ -d "$backup_file" ]]; then
                    info "Restoring directory: $file"
                    mkdir -p "$(dirname "$file")"
                    rm -rf "$file" 2>/dev/null || true
                    cp -r "$backup_file" "$(dirname "$file")/"
                fi
            done < "$manifest"
        else
            # Fallback: restore everything in backup directory
            warning "No manifest found, restoring all backup files"
            
            cd "$BACKUP_PATH"
            find . -type f -not -name "backup-manifest.txt" -not -name "backup-info.json" | while read -r file; do
                local target="$PROJECT_ROOT/${file#./}"
                
                # Skip special backup directories
                [[ "$file" == *".claude-complete"* ]] && continue
                
                info "Restoring: $file"
                mkdir -p "$(dirname "$target")"
                cp "$file" "$target"
            done
            cd "$PROJECT_ROOT"
            
            # Restore complete .claude directory if available
            if [[ -d "$BACKUP_PATH/.claude-complete" ]]; then
                info "Restoring complete .claude directory from backup"
                rm -rf .claude/* 2>/dev/null || true
                cp -r "$BACKUP_PATH/.claude-complete"/* .claude/ 2>/dev/null || true
            fi
        fi
        
        success "Preserved files restored from backup"
    fi
}

# Restore from git tag if available
function restore_from_git_tag() {
    if [[ "$GIT_TAG_EXISTS" == true ]] && git rev-parse --git-dir >/dev/null 2>&1; then
        local tag_name="ccpm-backup-$backup_name"
        
        confirm "Also restore git state to tag $tag_name?"
        
        info "Restoring git state from tag: $tag_name"
        
        # Reset to tag state (this will affect the entire repository)
        git reset --hard "$tag_name" || error_exit "Failed to reset to backup tag"
        
        success "Git state restored from backup tag"
    fi
}

# Validate restore
function validate_restore() {
    info "Validating restore..."
    
    # Check if critical files exist
    local critical_files=(".claude/VERSION" ".claude/commands" ".claude/agents")
    for file in "${critical_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            warning "Critical file/directory missing after restore: $file"
        else
            success "Found: $file"
        fi
    done
    
    # Show restored version
    if [[ -f ".claude/VERSION" ]]; then
        local restored_version=$(cat ".claude/VERSION")
        info "Restored Claude Code PM version: $restored_version"
    fi
    
    success "Restore validation completed"
}

# Main execution
function main() {
    # Show usage if no arguments
    if [[ $# -eq 0 ]]; then
        show_usage
    fi
    
    local backup_name="$1"
    
    info "Starting Claude Code PM restore process"
    info "Backup name: $backup_name"
    
    validate_environment
    find_backup "$backup_name"
    
    # Show what will be restored
    info "Restore plan:"
    if [[ "$BACKUP_FILES_EXIST" == true ]]; then
        info "  - Preserved files from: $BACKUP_PATH"
    fi
    if [[ "$GIT_TAG_EXISTS" == true ]]; then
        info "  - Git tag available: ccpm-backup-$backup_name"
    fi
    
    confirm "⚠️  This will overwrite current .claude files with backup data."
    
    restore_preserved_files
    restore_from_git_tag
    validate_restore
    
    success "Restore completed successfully!"
    info "Your project has been restored to backup: $backup_name"
    info ""
    info "Next steps:"
    info "  1. Review restored files"
    info "  2. Run validation: /pm:validate"
    info "  3. Test your project functionality"
    
    # Show what changed
    if git rev-parse --git-dir >/dev/null 2>&1; then
        if ! git diff-index --quiet HEAD --; then
            info ""
            info "Git status after restore:"
            git status --short || true
        fi
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi