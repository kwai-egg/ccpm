#!/bin/bash
# Script: github-utils.sh
# Purpose: GitHub API utilities for Claude Code PM update system
# Usage: source this file to use functions

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
    echo -e "${color}${message}${NC}" >&2
}

function error_exit() {
    log $RED "❌ Error: $1"
    exit 1
}

function info() {
    log $BLUE "ℹ️  $1"
}

function warning() {
    log $YELLOW "⚠️  $1"
}

function success() {
    log $GREEN "✅ $1"
}

function header() {
    log $BOLD "$1"
}

function dry_run_info() {
    log $CYAN "🔍 [DRY RUN] $1"
}

# Parse GitHub URL into owner and repo
function parse_github_url() {
    local url="$1"
    
    # Handle different GitHub URL formats using sed
    if [[ "$url" =~ ^https://github\.com/ ]]; then
        local parsed=$(echo "$url" | sed -E 's|https://github\.com/([^/]+)/([^/]+).*|\1 \2|')
        GITHUB_OWNER=$(echo "$parsed" | cut -d' ' -f1)
        GITHUB_REPO=$(echo "$parsed" | cut -d' ' -f2)
    elif [[ "$url" =~ ^git@github\.com: ]]; then
        local parsed=$(echo "$url" | sed -E 's|git@github\.com:([^/]+)/([^/]+).*|\1 \2|')
        GITHUB_OWNER=$(echo "$parsed" | cut -d' ' -f1)
        GITHUB_REPO=$(echo "$parsed" | cut -d' ' -f2)
    else
        error_exit "Invalid GitHub URL format: $url"
    fi
    
    # Remove .git suffix if present
    GITHUB_REPO="${GITHUB_REPO%.git}"
    
    # Validate we got both parts
    if [[ -z "$GITHUB_OWNER" || -z "$GITHUB_REPO" ]]; then
        error_exit "Could not parse GitHub URL: $url"
    fi
}

# Get raw file content from GitHub
function fetch_github_file() {
    local file_path="$1"
    local branch="${2:-main}"
    local owner="$GITHUB_OWNER"
    local repo="$GITHUB_REPO"
    
    # Try multiple methods in order of preference
    
    # Method 1: GitHub CLI (most reliable)
    if command -v gh >/dev/null 2>&1; then
        if gh api "repos/$owner/$repo/contents/$file_path?ref=$branch" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null; then
            return 0
        fi
    fi
    
    # Method 2: Raw githubusercontent (simple but reliable)
    local raw_url="https://raw.githubusercontent.com/$owner/$repo/$branch/$file_path"
    if curl -s -f "$raw_url" 2>/dev/null; then
        return 0
    fi
    
    # Method 3: GitHub API with curl
    local api_url="https://api.github.com/repos/$owner/$repo/contents/$file_path?ref=$branch"
    if command -v jq >/dev/null 2>&1; then
        local content=$(curl -s "$api_url" 2>/dev/null | jq -r '.content // empty' 2>/dev/null)
        if [[ -n "$content" && "$content" != "null" ]]; then
            echo "$content" | base64 -d 2>/dev/null && return 0
        fi
    fi
    
    return 1
}

# Get directory listing from GitHub
function fetch_github_tree() {
    local dir_path="$1"
    local branch="${2:-main}"
    local owner="$GITHUB_OWNER"
    local repo="$GITHUB_REPO"
    
    # Method 1: GitHub CLI
    if command -v gh >/dev/null 2>&1; then
        gh api "repos/$owner/$repo/contents/$dir_path?ref=$branch" --jq '.[] | select(.type == "file") | .path' 2>/dev/null && return 0
    fi
    
    # Method 2: GitHub API with curl
    if command -v jq >/dev/null 2>&1; then
        local api_url="https://api.github.com/repos/$owner/$repo/contents/$dir_path?ref=$branch"
        curl -s "$api_url" 2>/dev/null | jq -r '.[] | select(.type == "file") | .path' 2>/dev/null && return 0
    fi
    
    return 1
}

# Get recursive file listing
function fetch_github_tree_recursive() {
    local dir_path="$1"
    local branch="${2:-main}"
    local owner="$GITHUB_OWNER"
    local repo="$GITHUB_REPO"
    
    # Method 1: GitHub CLI with tree API
    if command -v gh >/dev/null 2>&1; then
        gh api "repos/$owner/$repo/git/trees/$branch?recursive=1" --jq '.tree[] | select(.type == "blob") | select(.path | startswith("'$dir_path'")) | .path' 2>/dev/null && return 0
    fi
    
    # Method 2: GitHub API with curl
    if command -v jq >/dev/null 2>&1; then
        local api_url="https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1"
        curl -s "$api_url" 2>/dev/null | jq -r '.tree[] | select(.type == "blob") | select(.path | startswith("'$dir_path'")) | .path' 2>/dev/null && return 0
    fi
    
    return 1
}

# Compare file checksums
function compare_file_checksums() {
    local local_file="$1"
    local remote_content="$2"
    
    if [[ ! -f "$local_file" ]]; then
        return 1  # Local file doesn't exist
    fi
    
    # Generate checksums
    local local_checksum=$(sha256sum "$local_file" 2>/dev/null | cut -d' ' -f1)
    local remote_checksum=$(echo "$remote_content" | sha256sum | cut -d' ' -f1)
    
    [[ "$local_checksum" == "$remote_checksum" ]]
}

# Get remote version
function get_remote_version() {
    local branch="${1:-main}"
    local version_content
    
    version_content=$(fetch_github_file ".claude/VERSION" "$branch")
    if [[ $? -eq 0 && -n "$version_content" ]]; then
        echo "$version_content" | tr -d '\n\r'
        return 0
    fi
    
    return 1
}

# Get remote changelog
function get_remote_changelog() {
    local branch="${1:-main}"
    
    fetch_github_file ".claude/CHANGELOG.md" "$branch"
}

# Check if file should be updated based on patterns
function should_update_file() {
    local file_path="$1"
    local config_file="${2:-.claude-pm.yaml}"
    
    # If no config file, update everything in .claude/
    if [[ ! -f "$config_file" ]]; then
        [[ "$file_path" =~ ^\.claude/ ]]
        return $?
    fi
    
    # Check update patterns
    local update_patterns=()
    if command -v yq >/dev/null 2>&1; then
        while IFS= read -r pattern; do
            update_patterns+=("$pattern")
        done < <(yq eval '.update[]' "$config_file" 2>/dev/null || echo "")
    else
        # Fallback: simple grep parsing
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*[\"\'](.+)[\"\'] ]]; then
                update_patterns+=("${BASH_REMATCH[1]}")
            fi
        done < <(sed -n '/^update:/,/^[a-z]/p' "$config_file" | grep -E "^\s*-" || echo "")
    fi
    
    # Check if file matches any update pattern
    for pattern in "${update_patterns[@]}"; do
        pattern=$(echo "$pattern" | sed 's/^"//' | sed 's/"$//')  # Remove quotes
        if [[ "$file_path" == $pattern || "$file_path" == ${pattern%/}/* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Check if file should be preserved
function should_preserve_file() {
    local file_path="$1"
    local config_file="${2:-.claude-pm.yaml}"
    
    # If no config file, preserve specific directories
    if [[ ! -f "$config_file" ]]; then
        [[ "$file_path" =~ ^\.claude/(epics|prds|context)/ ]]
        return $?
    fi
    
    # Check preserve patterns
    local preserve_patterns=()
    if command -v yq >/dev/null 2>&1; then
        while IFS= read -r pattern; do
            preserve_patterns+=("$pattern")
        done < <(yq eval '.preserve[]' "$config_file" 2>/dev/null || echo "")
    else
        # Fallback: simple grep parsing
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*[\"\'](.+)[\"\'] ]]; then
                preserve_patterns+=("${BASH_REMATCH[1]}")
            fi
        done < <(sed -n '/^preserve:/,/^[a-z]/p' "$config_file" | grep -E "^\s*-" || echo "")
    fi
    
    # Check if file matches any preserve pattern
    for pattern in "${preserve_patterns[@]}"; do
        pattern=$(echo "$pattern" | sed 's/^"//' | sed 's/"$//')  # Remove quotes
        if [[ "$file_path" == $pattern || "$file_path" == ${pattern%/}/* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Download and update a file
function update_file_from_github() {
    local file_path="$1"
    local branch="${2:-main}"
    local backup_dir="${3:-.ccpm-backups/update-$(date -u +%Y%m%d-%H%M%S)}"
    
    info "Updating: $file_path"
    
    # Create backup if file exists
    if [[ -f "$file_path" ]]; then
        mkdir -p "$backup_dir/$(dirname "$file_path")"
        cp "$file_path" "$backup_dir/$file_path" 2>/dev/null || true
    fi
    
    # Fetch remote content
    local remote_content
    remote_content=$(fetch_github_file "$file_path" "$branch")
    if [[ $? -ne 0 ]]; then
        log $RED "Failed to fetch remote content for: $file_path"
        return 1
    fi
    
    # Ensure directory exists
    mkdir -p "$(dirname "$file_path")"
    
    # Write content to file
    echo "$remote_content" > "$file_path"
    
    return 0
}

# Initialize GitHub utilities with repository info
function init_github_utils() {
    local upstream_url="$1"
    local branch="${2:-main}"
    
    parse_github_url "$upstream_url"
    GITHUB_BRANCH="$branch"
    
    info "GitHub utils initialized:"
    info "  Owner: $GITHUB_OWNER"
    info "  Repo: $GITHUB_REPO" 
    info "  Branch: $GITHUB_BRANCH"
}