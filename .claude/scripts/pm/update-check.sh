#!/bin/bash
# Script: update-check.sh
# Purpose: Check for available Claude Code PM updates
# Usage: ./update-check.sh

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.claude-pm.yaml"
VERSION_FILE="$PROJECT_ROOT/.claude/VERSION"

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

    # Check if version file exists
    if [[ ! -f "$VERSION_FILE" ]]; then
        warning "Version file not found: $VERSION_FILE"
        CURRENT_VERSION="unknown"
    else
        CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
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
}

# Setup upstream remote
function setup_upstream() {
    local remote_name="ccpm-upstream"
    
    # Check if upstream remote already exists
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
        local existing_url=$(git remote get-url "$remote_name")
        if [[ "$existing_url" != "$UPSTREAM_URL" ]]; then
            info "Updating upstream remote URL: $existing_url -> $UPSTREAM_URL"
            git remote set-url "$remote_name" "$UPSTREAM_URL"
        fi
    else
        info "Adding upstream remote: $UPSTREAM_URL"
        git remote add "$remote_name" "$UPSTREAM_URL"
    fi
    
    # Fetch latest from upstream
    info "Fetching latest updates from upstream..."
    git fetch "$remote_name" "$UPSTREAM_BRANCH" --quiet || error_exit "Failed to fetch from upstream"
    
    UPSTREAM_REMOTE="$remote_name"
}

# Get version information
function get_version_info() {
    # Current version
    info "Current version: $CURRENT_VERSION"
    
    # Upstream version
    local upstream_version_file="$UPSTREAM_REMOTE/$UPSTREAM_BRANCH:.claude/VERSION"
    if git show "$upstream_version_file" >/dev/null 2>&1; then
        UPSTREAM_VERSION=$(git show "$upstream_version_file" 2>/dev/null | tr -d '\n' | tr -d '\r')
        info "Upstream version: $UPSTREAM_VERSION"
    else
        warning "Could not determine upstream version"
        UPSTREAM_VERSION="unknown"
    fi
}

# Compare versions using semantic versioning
function compare_versions() {
    if [[ "$CURRENT_VERSION" == "unknown" || "$UPSTREAM_VERSION" == "unknown" ]]; then
        warning "Cannot compare versions (one or both unknown)"
        return 2
    fi
    
    if [[ "$CURRENT_VERSION" == "$UPSTREAM_VERSION" ]]; then
        return 0  # Same version
    fi
    
    # Simple version comparison (assumes semantic versioning)
    local current_parts=(${CURRENT_VERSION//./ })
    local upstream_parts=(${UPSTREAM_VERSION//./ })
    
    for i in {0..2}; do
        local current_part=${current_parts[i]:-0}
        local upstream_part=${upstream_parts[i]:-0}
        
        if (( current_part < upstream_part )); then
            return 1  # Upstream is newer
        elif (( current_part > upstream_part )); then
            return -1  # Current is newer
        fi
    done
    
    return 0  # Same version
}

# Show changes since current version
function show_changes() {
    header "\n📋 Changes Available:"
    
    # Try to show changelog from upstream
    local upstream_changelog="$UPSTREAM_REMOTE/$UPSTREAM_BRANCH:.claude/CHANGELOG.md"
    if git show "$upstream_changelog" >/dev/null 2>&1; then
        # Extract relevant changelog entries
        local changelog_content=$(git show "$upstream_changelog" 2>/dev/null)
        
        # Show changelog (limit to reasonable size)
        echo "$changelog_content" | head -50 | tail -n +10
    else
        # Fallback: show commit differences
        warning "No changelog available, showing recent commits:"
        git log --oneline "HEAD..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" | head -10
    fi
}

# Show file differences
function show_file_changes() {
    header "\n📁 Files That Would Be Updated:"
    
    # Get list of changed files
    local changed_files=$(git diff --name-only "HEAD" "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || true)
    
    if [[ -z "$changed_files" ]]; then
        success "No file changes detected"
        return
    fi
    
    # Parse update patterns from config
    local update_patterns=()
    if command -v yq >/dev/null 2>&1; then
        while IFS= read -r pattern; do
            update_patterns+=("$pattern")
        done < <(yq eval '.update[]' "$CONFIG_FILE" 2>/dev/null || true)
    else
        # Fallback parsing
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*-[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
                pattern="${BASH_REMATCH[1]}"
                update_patterns+=("$pattern")
            fi
        done < <(sed -n '/^update:/,/^[a-z]/p' "$CONFIG_FILE" | grep -E "^\s*-" || true)
    fi
    
    # Show which files would be updated
    echo "$changed_files" | while read -r file; do
        local will_update=false
        
        for pattern in "${update_patterns[@]}"; do
            # Remove quotes and check if file matches pattern
            pattern=$(echo "$pattern" | sed 's/^"//' | sed 's/"$//')
            if [[ "$file" == $pattern || "$file" == ${pattern%/}/* ]]; then
                will_update=true
                break
            fi
        done
        
        if [[ "$will_update" == true ]]; then
            log $GREEN "  ✅ $file (will be updated)"
        else
            log $YELLOW "  ⏭️  $file (preserved - no changes)"
        fi
    done
}

# Show status summary
function show_status_summary() {
    header "\n📊 Update Status Summary:"
    
    compare_versions
    local version_result=$?
    
    case $version_result in
        0)
            success "You are up to date! (version $CURRENT_VERSION)"
            return 0
            ;;
        1)
            warning "Update available: $CURRENT_VERSION -> $UPSTREAM_VERSION"
            info "Run '/pm:update' to apply updates"
            return 1
            ;;
        -1)
            info "You are ahead of upstream: $CURRENT_VERSION > $UPSTREAM_VERSION"
            info "This might be a development version"
            return 0
            ;;
        2)
            warning "Cannot determine update status (version comparison failed)"
            info "You may want to run '/pm:update' to ensure you have the latest"
            return 2
            ;;
    esac
}

# Main execution
function main() {
    header "🔍 Claude Code PM Update Check"
    
    cd "$PROJECT_ROOT" || error_exit "Could not change to project root"
    
    validate_environment
    read_config
    setup_upstream
    get_version_info
    
    # Check if updates are available
    compare_versions
    local update_status=$?
    
    if [[ $update_status -eq 1 ]]; then
        # Updates available
        show_changes
        show_file_changes
    fi
    
    show_status_summary
    
    info "\nTo apply updates: /pm:update"
    info "To see more details: /pm:update --dry-run"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi