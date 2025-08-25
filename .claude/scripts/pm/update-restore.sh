#!/bin/bash
# Script: update-restore.sh
# Purpose: Restore from Claude Code PM backup
# Usage: ./update-restore.sh [backup-name]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.claude-pm.yaml"
BACKUP_DIR="$PROJECT_ROOT/.ccpm-backups"

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
    
    # List git backup branches
    echo ""
    echo "Git branches:"
    git branch | grep "ccpm-backup-" | sed 's/^[* ] /  /' || echo "  (no backup branches found)"
    
    # List backup directories
    echo ""
    echo "File backups:"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -1t "$BACKUP_DIR" | grep "^backup-" | sed 's/^/  /' || echo "  (no backup directories found)"
    else
        echo "  (no backup directory found)"
    fi
    
    exit 1
}

# Validate environment
function validate_environment() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error_exit "Not in a git repository"
    fi

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        confirm "⚠️  You have uncommitted changes. Restoring will overwrite them."
    fi
}

# Find backup by name
function find_backup() {
    local backup_name="$1"
    
    # Check for git branch
    BACKUP_BRANCH="ccpm-backup-$backup_name"
    if git show-ref --verify --quiet "refs/heads/$BACKUP_BRANCH"; then
        BACKUP_BRANCH_EXISTS=true
        info "Found backup branch: $BACKUP_BRANCH"
    else
        BACKUP_BRANCH_EXISTS=false
        warning "Backup branch not found: $BACKUP_BRANCH"
    fi
    
    # Check for file backup
    BACKUP_PATH="$BACKUP_DIR/$backup_name"
    if [[ -d "$BACKUP_PATH" ]]; then
        BACKUP_FILES_EXIST=true
        info "Found backup files: $BACKUP_PATH"
    else
        BACKUP_FILES_EXIST=false
        warning "Backup files not found: $BACKUP_PATH"
    fi
    
    # Must have at least one type of backup
    if [[ "$BACKUP_BRANCH_EXISTS" == false && "$BACKUP_FILES_EXIST" == false ]]; then
        error_exit "No backup found with name: $backup_name"
    fi
}

# Restore from git branch
function restore_from_branch() {
    if [[ "$BACKUP_BRANCH_EXISTS" == true ]]; then
        info "Restoring git state from branch: $BACKUP_BRANCH"
        
        # Reset to backup branch state
        git reset --hard "$BACKUP_BRANCH" || error_exit "Failed to reset to backup branch"
        
        success "Git state restored from backup branch"
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
            
            # Restore files listed in manifest
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^#.*$ ]] && continue
                [[ -z "$line" ]] && continue
                
                local file="$line"
                local backup_file="$BACKUP_PATH/$file"
                
                if [[ -f "$backup_file" ]]; then
                    info "Restoring file: $file"
                    mkdir -p "$(dirname "$file")"
                    cp "$backup_file" "$file"
                elif [[ -d "$backup_file" ]]; then
                    info "Restoring directory: $file"
                    mkdir -p "$(dirname "$file")"
                    cp -r "$backup_file" "$(dirname "$file")/"
                fi
            done < "$manifest"
        else
            # Fallback: restore everything in backup directory
            warning "No manifest found, restoring all backup files"
            
            cd "$BACKUP_PATH"
            find . -type f -not -name "backup-manifest.txt" | while read -r file; do
                local target="$PROJECT_ROOT/${file#./}"
                info "Restoring: $file"
                mkdir -p "$(dirname "$target")"
                cp "$file" "$target"
            done
            cd "$PROJECT_ROOT"
        fi
        
        success "Preserved files restored from backup"
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
        fi
    done
    
    # Check git status
    if git diff-index --quiet HEAD --; then
        success "Git working directory is clean"
    else
        info "Git working directory has changes (this may be expected)"
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
    
    cd "$PROJECT_ROOT" || error_exit "Could not change to project root"
    
    validate_environment
    find_backup "$backup_name"
    
    # Show what will be restored
    info "Restore plan:"
    if [[ "$BACKUP_BRANCH_EXISTS" == true ]]; then
        info "  - Git state from branch: $BACKUP_BRANCH"
    fi
    if [[ "$BACKUP_FILES_EXIST" == true ]]; then
        info "  - Preserved files from: $BACKUP_PATH"
    fi
    
    confirm "⚠️  This will overwrite current files with backup data."
    
    restore_from_branch
    restore_preserved_files
    validate_restore
    
    success "Restore completed successfully!"
    info "Your project has been restored to backup: $backup_name"
    info ""
    info "Next steps:"
    info "  1. Review restored files"
    info "  2. Run validation: /pm:validate"
    info "  3. Test your project functionality"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi