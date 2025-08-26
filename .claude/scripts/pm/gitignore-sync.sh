#!/bin/bash
# Script: gitignore-sync.sh
# Purpose: Synchronize project .gitignore with ~/.claude/.claude-pm.yaml configuration
# Usage: ./gitignore-sync.sh

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_PM_YAML="$PROJECT_ROOT/~/.claude/.claude-pm.yaml"
GITIGNORE_FILE="$PROJECT_ROOT/.gitignore"
TEMP_FILE="$(mktemp)"

# Markers for managed section
START_MARKER="# === Claude Code PM (auto-managed) ==="
END_MARKER="# === End Claude Code PM ==="

function main() {
    echo "🔄 Synchronizing .gitignore with ~/.claude/.claude-pm.yaml"
    
    # Validate prerequisites
    validate_files
    
    # Parse YAML configuration
    local update_paths
    local preserve_paths
    update_paths=$(extract_yaml_paths "update")
    preserve_paths=$(extract_yaml_paths "preserve")
    
    # Generate managed section content
    local managed_content
    managed_content=$(generate_managed_section "$update_paths")
    
    # Update .gitignore file
    update_gitignore_file "$managed_content"
    
    echo "✅ .gitignore synchronized successfully"
    
    # Show what was managed
    if [[ -n "$update_paths" ]]; then
        echo "📝 Added to .gitignore:"
        echo "$update_paths" | while read -r path; do
            [[ -n "$path" ]] && echo "  - $path"
        done
    fi
}

function validate_files() {
    if [[ ! -f "$CLAUDE_PM_YAML" ]]; then
        error_exit "Configuration file not found: $CLAUDE_PM_YAML"
    fi
    
    if [[ ! -r "$CLAUDE_PM_YAML" ]]; then
        error_exit "Cannot read configuration file: $CLAUDE_PM_YAML"
    fi
    
    # Create .gitignore if it doesn't exist
    if [[ ! -f "$GITIGNORE_FILE" ]]; then
        echo "📄 Creating new .gitignore file"
        touch "$GITIGNORE_FILE"
    fi
}

function extract_yaml_paths() {
    local section="$1"
    local in_section=false
    local paths=""
    
    while IFS= read -r line; do
        # Check for section start (ignoring leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*${section}:[[:space:]]*$ ]]; then
            in_section=true
            continue
        fi
        
        # Check for next section (exit current)
        if [[ "$in_section" == true && "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*$ ]]; then
            break
        fi
        
        # Extract paths from current section (looking for "  - " pattern)
        if [[ "$in_section" == true && "$line" =~ ^[[:space:]]*-[[:space:]]* ]]; then
            # Extract path and clean quotes
            local path="${line#*- }"
            
            # Remove comments (everything after #)
            path="${path%%#*}"
            # Trim whitespace
            path="${path## }"
            path="${path%% }"
            
            # Remove all quotes
            path=$(echo "$path" | tr -d '"'"'")
            
            if [[ -n "$path" ]]; then
                paths="$paths$path"$'\n'
            fi
        fi
    done < "$CLAUDE_PM_YAML"
    
    echo "$paths"
}

function generate_managed_section() {
    local update_paths="$1"
    local content=""
    
    content+="$START_MARKER"$'\n'
    content+="# DO NOT EDIT THIS SECTION MANUALLY"$'\n'
    content+="# Managed by .claude/scripts/pm/gitignore-sync.sh"$'\n'
    
    if [[ -n "$update_paths" ]]; then
        echo "$update_paths" | while IFS= read -r path; do
            [[ -n "$path" ]] && echo "$path"
        done | sort -u >> "$TEMP_FILE.paths"
        
        while IFS= read -r path; do
            [[ -n "$path" ]] && content+="$path"$'\n'
        done < "$TEMP_FILE.paths"
        
        rm -f "$TEMP_FILE.paths"
    fi
    
    # Add system files that should always be ignored
    content+=".ccpm-backups/"$'\n'
    content+=".claude/.last-update-check"$'\n'
    
    content+="$END_MARKER"
    
    echo "$content"
}

function update_gitignore_file() {
    local managed_content="$1"
    local before_managed=""
    local after_managed=""
    local in_managed=false
    local found_managed=false
    
    # Read existing .gitignore and separate managed/unmanaged sections
    if [[ -f "$GITIGNORE_FILE" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "$START_MARKER" ]]; then
                in_managed=true
                found_managed=true
                continue
            elif [[ "$line" == "$END_MARKER" ]]; then
                in_managed=false
                continue
            fi
            
            if [[ "$in_managed" == false ]]; then
                if [[ "$found_managed" == true ]]; then
                    after_managed+="$line"$'\n'
                else
                    before_managed+="$line"$'\n'
                fi
            fi
        done < "$GITIGNORE_FILE"
    fi
    
    # Write new .gitignore
    {
        # Before managed section
        if [[ -n "$before_managed" ]]; then
            echo -n "$before_managed"
            # Add blank line if before_managed doesn't end with one
            if [[ "$before_managed" != *$'\n'$'\n' && "$before_managed" != *$'\n' ]]; then
                echo
            fi
        fi
        
        # Managed section
        echo "$managed_content"
        
        # After managed section
        if [[ -n "$after_managed" ]]; then
            echo
            echo -n "$after_managed"
        fi
    } > "$TEMP_FILE"
    
    # Replace original file
    mv "$TEMP_FILE" "$GITIGNORE_FILE"
}

function error_exit() {
    echo "❌ Error: $1" >&2
    cleanup
    exit 1
}

function cleanup() {
    rm -f "$TEMP_FILE" "$TEMP_FILE.paths"
}

# Trap cleanup on exit
trap cleanup EXIT

# Execute main function
main "$@"