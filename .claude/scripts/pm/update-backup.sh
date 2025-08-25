#!/bin/bash
# Script: update-backup.sh
# Purpose: Create backup of current state before Claude Code PM update
# Usage: ./update-backup.sh [backup-name]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.claude-pm.yaml"
BACKUP_DIR="$PROJECT_ROOT/.ccpm-backups"

# Default backup name with timestamp
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
BACKUP_NAME="${1:-backup-$TIMESTAMP}"
BACKUP_BRANCH="ccpm-backup-$BACKUP_NAME"

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

# Validate environment
function validate_environment() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error_exit "Not in a git repository"
    fi

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE"
    fi

    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
}

# Parse YAML configuration
function read_config() {
    # Simple YAML parsing for our specific structure
    if command -v yq >/dev/null 2>&1; then
        # Use yq if available (more reliable)
        KEEP_BACKUPS=$(yq eval '.backup.keep_backups // 5' "$CONFIG_FILE")
    else
        # Fallback to grep/sed parsing
        KEEP_BACKUPS=$(grep -E "^\s*keep_backups:" "$CONFIG_FILE" | sed 's/.*: *//' | sed 's/#.*//' | tr -d ' ' || echo "5")
        # Default to 5 if parsing fails
        KEEP_BACKUPS=${KEEP_BACKUPS:-5}
    fi
}

# Create git backup branch
function create_backup_branch() {
    info "Creating backup branch: $BACKUP_BRANCH"
    
    # Create a new branch from current HEAD
    git branch "$BACKUP_BRANCH" HEAD || error_exit "Failed to create backup branch"
    
    success "Backup branch created: $BACKUP_BRANCH"
}

# Backup preserved files to directory
function backup_preserved_files() {
    info "Backing up preserved files to $BACKUP_DIR/$BACKUP_NAME"
    
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    mkdir -p "$backup_path"
    
    # Create backup manifest
    cat > "$backup_path/backup-manifest.txt" << EOF
# Claude Code PM Backup Manifest
# Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Branch: $BACKUP_BRANCH
# Working Directory: $(pwd)
# Git Commit: $(git rev-parse HEAD)

# Preserved Files:
EOF

    # Parse preserve list from config and backup files
    local preserve_patterns=()
    if command -v yq >/dev/null 2>&1; then
        # Use yq for reliable YAML parsing
        while IFS= read -r pattern; do
            preserve_patterns+=("$pattern")
        done < <(yq eval '.preserve[]' "$CONFIG_FILE")
    else
        # Fallback parsing
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
                pattern="${BASH_REMATCH[1]}"
                preserve_patterns+=("$pattern")
            fi
        done < <(sed -n '/^preserve:/,/^[a-z]/p' "$CONFIG_FILE" | grep -E "^\s*-")
    fi

    # Backup each preserved pattern
    for pattern in "${preserve_patterns[@]}"; do
        # Remove surrounding quotes
        pattern=$(echo "$pattern" | sed 's/^"//' | sed 's/"$//')
        
        # Skip if pattern starts with / (absolute path)
        if [[ "$pattern" == /* ]]; then
            continue
        fi
        
        # Handle directories vs files
        if [[ "$pattern" == */ ]]; then
            # Directory pattern
            local dir_pattern="${pattern%/}"
            if [[ -d "$dir_pattern" ]]; then
                info "Backing up directory: $dir_pattern"
                mkdir -p "$backup_path/$(dirname "$dir_pattern")"
                cp -r "$dir_pattern" "$backup_path/$(dirname "$dir_pattern")/" 2>/dev/null || warning "Could not backup $dir_pattern"
                echo "$dir_pattern/" >> "$backup_path/backup-manifest.txt"
            fi
        else
            # File pattern (may include wildcards)
            while IFS= read -r -d '' file; do
                if [[ -f "$file" ]]; then
                    info "Backing up file: $file"
                    mkdir -p "$backup_path/$(dirname "$file")"
                    cp "$file" "$backup_path/$file"
                    echo "$file" >> "$backup_path/backup-manifest.txt"
                fi
            done < <(find . -path "./$pattern" -print0 2>/dev/null || true)
        fi
    done
    
    success "Files backed up to $backup_path"
}

# Clean up old backups
function cleanup_old_backups() {
    info "Cleaning up old backups (keeping $KEEP_BACKUPS most recent)"
    
    # Clean up old backup branches
    local backup_branches=($(git branch | grep "ccpm-backup-" | sed 's/^[* ] //' | sort))
    local num_branches=${#backup_branches[@]}
    
    if [[ $num_branches -gt $KEEP_BACKUPS ]]; then
        local to_delete=$((num_branches - KEEP_BACKUPS))
        for ((i=0; i<to_delete; i++)); do
            local branch_to_delete="${backup_branches[$i]}"
            info "Deleting old backup branch: $branch_to_delete"
            git branch -D "$branch_to_delete" || warning "Could not delete branch $branch_to_delete"
        done
    fi
    
    # Clean up old backup directories
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_dirs=($(ls -1t "$BACKUP_DIR" 2>/dev/null | grep "^backup-" || true))
        local num_dirs=${#backup_dirs[@]}
        
        if [[ $num_dirs -gt $KEEP_BACKUPS ]]; then
            local to_delete=$((num_dirs - KEEP_BACKUPS))
            for ((i=$KEEP_BACKUPS; i<num_dirs; i++)); do
                local dir_to_delete="$BACKUP_DIR/${backup_dirs[$i]}"
                info "Deleting old backup directory: $dir_to_delete"
                rm -rf "$dir_to_delete" || warning "Could not delete directory $dir_to_delete"
            done
        fi
    fi
    
    success "Backup cleanup completed"
}

# Main execution
function main() {
    info "Starting Claude Code PM backup process"
    info "Backup name: $BACKUP_NAME"
    
    cd "$PROJECT_ROOT" || error_exit "Could not change to project root"
    
    validate_environment
    read_config
    create_backup_branch
    backup_preserved_files
    cleanup_old_backups
    
    success "Backup completed successfully!"
    info "Backup branch: $BACKUP_BRANCH"
    info "Backup files: $BACKUP_DIR/$BACKUP_NAME"
    info "To restore this backup later, run:"
    info "  ./.claude/scripts/pm/update-restore.sh $BACKUP_NAME"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi