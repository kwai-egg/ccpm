#!/bin/bash
# Script: update-backup.sh (rewritten for non-git .claude folders)
# Purpose: Create backup of current state before Claude Code PM update
# Usage: ./update-backup.sh [backup-name]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$CLAUDE_DIR/.claude-pm.yaml"
BACKUP_DIR="$CLAUDE_DIR/.ccpm-backups"

# Default backup name with timestamp
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
BACKUP_NAME="${1:-backup-$TIMESTAMP}"

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
    # Check if .claude directory exists
    if [[ ! -d "$PROJECT_ROOT/.claude" ]]; then
        error_exit "Claude Code PM not found (.claude directory missing)"
    fi

    # Check if config file exists (create minimal config if missing)
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warning "Configuration file not found, using default preserve patterns"
        # Create temporary minimal config
        cat > "$CONFIG_FILE.tmp" << EOF
preserve:
  - ".claude/epics/"
  - ".claude/prds/"
  - ".claude/context/"
  - ".claude/CLAUDE.md"
  - ".claude/**/*.local.*"
EOF
        CONFIG_FILE="$CONFIG_FILE.tmp"
    fi

    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
}

# Parse YAML configuration
function read_config() {
    # Simple YAML parsing for our specific structure
    if command -v yq >/dev/null 2>&1; then
        # Use yq if available (more reliable)
        KEEP_BACKUPS=$(yq eval '.backup.keep_backups // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
    else
        # Fallback to grep/sed parsing
        KEEP_BACKUPS=$(grep -E "^\s*keep_backups:" "$CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | sed 's/#.*//' | tr -d ' ' || echo "5")
        # Default to 5 if parsing fails
        KEEP_BACKUPS=${KEEP_BACKUPS:-5}
    fi
}

# Backup preserved files to directory
function backup_preserved_files() {
    info "Backing up files to $BACKUP_DIR/$BACKUP_NAME"
    
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    mkdir -p "$backup_path"
    
    # Create backup manifest
    cat > "$backup_path/backup-manifest.txt" << EOF
# Claude Code PM Backup Manifest
# Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Working Directory: $(pwd)
# Backup Type: File-based (no git branches)

# Preserved Files:
EOF

    # Parse preserve list from config and backup files
    local preserve_patterns=()
    if command -v yq >/dev/null 2>&1; then
        # Use yq for reliable YAML parsing
        while IFS= read -r pattern; do
            preserve_patterns+=("$pattern")
        done < <(yq eval '.preserve[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    else
        # Fallback parsing
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*[\"\'](.+)[\"\'] ]]; then
                pattern="${BASH_REMATCH[1]}"
                preserve_patterns+=("$pattern")
            fi
        done < <(sed -n '/^preserve:/,/^[a-z]/p' "$CONFIG_FILE" | grep -E "^\s*-" 2>/dev/null || echo "")
    fi
    
    # Default patterns if none found
    if [[ ${#preserve_patterns[@]} -eq 0 ]]; then
        preserve_patterns=(
            ".claude/epics/"
            ".claude/prds/"
            ".claude/context/"
            ".claude/CLAUDE.md"
            ".claude/**/*.local.*"
        )
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
            if [[ "$pattern" == *"*"* ]]; then
                # Handle wildcard patterns
                find . -path "./$pattern" 2>/dev/null | while IFS= read -r -d '' file || [[ -n "$file" ]]; do
                    if [[ -f "$file" ]]; then
                        info "Backing up file: $file"
                        mkdir -p "$backup_path/$(dirname "$file")"
                        cp "$file" "$backup_path/$file"
                        echo "$file" >> "$backup_path/backup-manifest.txt"
                    fi
                done
            else
                # Simple file pattern
                if [[ -f "$pattern" ]]; then
                    info "Backing up file: $pattern"
                    mkdir -p "$backup_path/$(dirname "$pattern")"
                    cp "$pattern" "$backup_path/$pattern"
                    echo "$pattern" >> "$backup_path/backup-manifest.txt"
                fi
            fi
        fi
    done
    
    # Also backup the entire .claude directory as a safety net
    if [[ -d ".claude" ]]; then
        info "Backing up complete .claude directory as safety net"
        mkdir -p "$backup_path/.claude-complete"
        cp -r .claude/* "$backup_path/.claude-complete/" 2>/dev/null || true
        echo ".claude/ (complete)" >> "$backup_path/backup-manifest.txt"
    fi
    
    # Backup configuration files
    for config_file in ".claude/.claude-pm.yaml" "CLAUDE.md"; do
        if [[ -f "$config_file" ]]; then
            info "Backing up config: $config_file"
            cp "$config_file" "$backup_path/"
            echo "$config_file" >> "$backup_path/backup-manifest.txt"
        fi
    done
    
    # Create backup metadata
    cat > "$backup_path/backup-info.json" << EOF
{
  "backup_name": "$BACKUP_NAME",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "working_directory": "$(pwd)",
  "backup_type": "file-based",
  "claude_version": "$(cat .claude/VERSION 2>/dev/null || echo 'unknown')"
}
EOF
    
    success "Files backed up to $backup_path"
}

# Clean up old backups
function cleanup_old_backups() {
    info "Cleaning up old backups (keeping $KEEP_BACKUPS most recent)"
    
    # Clean up old backup directories
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_dirs=($(ls -1t "$BACKUP_DIR" 2>/dev/null | grep "^backup-" | head -20 || true))
        local num_dirs=${#backup_dirs[@]}
        
        if [[ $num_dirs -gt $KEEP_BACKUPS ]]; then
            local to_delete=$((num_dirs - KEEP_BACKUPS))
            for ((i=$KEEP_BACKUPS; i<num_dirs; i++)); do
                local dir_to_delete="$BACKUP_DIR/${backup_dirs[$i]}"
                if [[ -d "$dir_to_delete" ]]; then
                    info "Deleting old backup directory: ${backup_dirs[$i]}"
                    rm -rf "$dir_to_delete" || warning "Could not delete directory $dir_to_delete"
                fi
            done
        fi
    fi
    
    success "Backup cleanup completed"
}

# Create git snapshot if in git repo (optional)
function create_git_snapshot() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        info "Creating git snapshot (optional)"
        
        # Create a tag for this backup
        local tag_name="ccpm-backup-$BACKUP_NAME"
        
        # Check if there are changes to commit
        if ! git diff-index --quiet HEAD --; then
            warning "Git working directory has changes, cannot create clean snapshot"
            return
        fi
        
        if git tag "$tag_name" 2>/dev/null; then
            info "Git tag created: $tag_name"
            echo "git_tag=$tag_name" >> "$BACKUP_DIR/$BACKUP_NAME/backup-info.json.tmp"
            if [[ -f "$BACKUP_DIR/$BACKUP_NAME/backup-info.json.tmp" ]]; then
                mv "$BACKUP_DIR/$BACKUP_NAME/backup-info.json.tmp" "$BACKUP_DIR/$BACKUP_NAME/backup-info.json"
            fi
        else
            warning "Could not create git tag (tag may already exist)"
        fi
    fi
}

# Main execution
function main() {
    info "Starting Claude Code PM backup process"
    info "Backup name: $BACKUP_NAME"
    
    validate_environment
    read_config
    backup_preserved_files
    create_git_snapshot
    cleanup_old_backups
    
    # Clean up temporary config if created
    if [[ -f "$CONFIG_FILE.tmp" ]]; then
        rm -f "$CONFIG_FILE.tmp"
    fi
    
    success "Backup completed successfully!"
    info "Backup location: $BACKUP_DIR/$BACKUP_NAME"
    info "To restore this backup later, run:"
    info "  ./.claude/scripts/pm/update-restore.sh $BACKUP_NAME"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi