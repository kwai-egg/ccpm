#!/bin/bash
# Script: path-resolver.sh
# Purpose: Resolve script and resource paths for both project-local and global Claude installations
# Usage: source path-resolver.sh

# Determine if we're running from a global or project-local installation
function determine_installation_type() {
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if we're in a home directory installation (either ~/.claude or ~/.ccpm)
    if [[ "$script_path" == "$HOME/.claude"* ]] || [[ "$script_path" == "$HOME/.ccpm"* ]]; then
        echo "global"
    else
        echo "project"
    fi
}

# Get the Claude directory path
function get_claude_dir() {
    local installation_type="${1:-$(determine_installation_type)}"
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ "$installation_type" == "global" ]]; then
        # For global installation, find the .claude directory from the script path
        if [[ "$script_path" == "$HOME/.ccpm"* ]]; then
            # We're in ~/.ccpm/.claude/scripts/pm, go back to .claude
            echo "$(cd "$script_path/../.." && pwd)"
        else
            # We're in ~/.claude directly
            echo "$HOME/.claude"
        fi
    else
        # For project installation, find the .claude directory relative to script
        echo "$(cd "$script_path/../.." && pwd)"
    fi
}

# Get the project root directory
function get_project_root() {
    local installation_type="${1:-$(determine_installation_type)}"
    
    if [[ "$installation_type" == "global" ]]; then
        # For global installation, project root is the current working directory
        echo "$(pwd)"
    else
        # For project installation, go up from .claude to project root
        local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        echo "$(cd "$script_path/../../.." && pwd)"
    fi
}

# Get the scripts directory
function get_scripts_dir() {
    local installation_type="${1:-$(determine_installation_type)}"
    echo "$(get_claude_dir "$installation_type")/scripts"
}

# Resolve a script path (checks both locations if needed)
function resolve_script() {
    local script_name="$1"
    local prefer_global="${2:-false}"
    
    # Remove leading ./ or / if present
    script_name="${script_name#./}"
    script_name="${script_name#/}"
    
    # Check if it's already a full path
    if [[ -f "$script_name" ]]; then
        echo "$script_name"
        return 0
    fi
    
    # Try global location first if preferred
    if [[ "$prefer_global" == "true" ]] && [[ -f "$HOME/.claude/scripts/$script_name" ]]; then
        echo "$HOME/.claude/scripts/$script_name"
        return 0
    fi
    
    # Try project-local location
    if [[ -f "./.claude/scripts/$script_name" ]]; then
        echo "./.claude/scripts/$script_name"
        return 0
    fi
    
    # Try global location as fallback
    if [[ -f "$HOME/.claude/scripts/$script_name" ]]; then
        echo "$HOME/.claude/scripts/$script_name"
        return 0
    fi
    
    # Script not found
    return 1
}

# Resolve a command or agent definition path
function resolve_definition() {
    local def_type="$1"  # "commands" or "agents"
    local def_name="$2"
    local prefer_global="${3:-false}"
    
    # Remove .md extension if provided
    def_name="${def_name%.md}"
    
    # Try global location first if preferred
    if [[ "$prefer_global" == "true" ]] && [[ -f "$HOME/.claude/$def_type/$def_name.md" ]]; then
        echo "$HOME/.claude/$def_type/$def_name.md"
        return 0
    fi
    
    # Try project-local location
    if [[ -f "./.claude/$def_type/$def_name.md" ]]; then
        echo "./.claude/$def_type/$def_name.md"
        return 0
    fi
    
    # Try global location as fallback
    if [[ -f "$HOME/.claude/$def_type/$def_name.md" ]]; then
        echo "$HOME/.claude/$def_type/$def_name.md"
        return 0
    fi
    
    # Definition not found
    return 1
}

# Check if we should use global resources
function should_use_global() {
    # Check for environment variable override
    if [[ -n "${CLAUDE_USE_GLOBAL:-}" ]]; then
        echo "$CLAUDE_USE_GLOBAL"
        return 0
    fi
    
    # Check if project has its own .claude directory
    if [[ -d "./.claude" ]]; then
        # Project has local .claude, use it by default
        echo "false"
    else
        # No local .claude, use global
        echo "true"
    fi
}

# Export variables for use in other scripts
export INSTALLATION_TYPE="$(determine_installation_type)"
export CLAUDE_DIR="$(get_claude_dir)"
export PROJECT_ROOT="$(get_project_root)"
export SCRIPTS_DIR="$(get_scripts_dir)"

# Export functions for use in sourced scripts
export -f determine_installation_type
export -f get_claude_dir
export -f get_project_root
export -f get_scripts_dir
export -f resolve_script
export -f resolve_definition
export -f should_use_global