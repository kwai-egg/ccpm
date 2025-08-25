#!/bin/bash
# Script: update-check.sh (rewritten for non-git .claude folders)
# Purpose: Check for available Claude Code PM updates using GitHub API
# Usage: ./update-check.sh [--verbose] [--quiet]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
CONFIG_FILE="$PROJECT_ROOT/.claude-pm.yaml"
VERSION_FILE="$PROJECT_ROOT/.claude/VERSION"

# Parse command line arguments
VERBOSE=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --quiet)
            QUIET=true
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
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE"
    fi

    # Check if .claude directory exists
    if [[ ! -d "$PROJECT_ROOT/.claude" ]]; then
        error_exit "Claude Code PM not found (.claude directory missing)"
    fi

    # Get current version
    if [[ -f "$VERSION_FILE" ]]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
    else
        CURRENT_VERSION="unknown"
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

# Get version information
function get_version_info() {
    # Initialize GitHub utilities
    init_github_utils "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
    
    if [[ "$QUIET" != true ]]; then
        info "Current version: $CURRENT_VERSION"
    fi
    
    # Get upstream version
    UPSTREAM_VERSION=$(get_remote_version "$UPSTREAM_BRANCH")
    if [[ $? -eq 0 && -n "$UPSTREAM_VERSION" ]]; then
        if [[ "$QUIET" != true ]]; then
            info "Upstream version: $UPSTREAM_VERSION"
        fi
    else
        if [[ "$QUIET" != true ]]; then
            error_exit "Could not determine upstream version"
        else
            echo "UPDATE_STATUS=error"
            echo "ERROR=cannot_determine_upstream_version"
            exit 2
        fi
    fi
}

# Compare versions using semantic versioning
function compare_versions() {
    if [[ "$CURRENT_VERSION" == "unknown" || "$UPSTREAM_VERSION" == "unknown" ]]; then
        if [[ "$QUIET" == true ]]; then
            echo "UPDATE_STATUS=unknown"
            echo "CURRENT_VERSION=$CURRENT_VERSION"
            echo "UPSTREAM_VERSION=$UPSTREAM_VERSION"
        else
            warning "Cannot compare versions (one or both unknown)"
        fi
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
    if [[ "$QUIET" == true ]]; then
        return
    fi
    
    header "\n📋 Changes Available:"
    
    # Get changelog from upstream
    local changelog_content
    changelog_content=$(get_remote_changelog "$UPSTREAM_BRANCH")
    if [[ $? -eq 0 && -n "$changelog_content" ]]; then
        # Show changelog (limit to reasonable size)
        echo "$changelog_content" | head -50 | tail -n +10
    else
        warning "Changelog not available from upstream"
    fi
}

# Show file differences
function show_file_changes() {
    if [[ "$QUIET" == true ]]; then
        return
    fi
    
    header "\n📁 Files That Would Be Updated:"
    
    # Get list of files that should be updated
    local update_candidates=()
    
    # Get files from upstream .claude directory
    local remote_files
    remote_files=$(fetch_github_tree_recursive ".claude" "$UPSTREAM_BRANCH")
    if [[ $? -ne 0 ]]; then
        warning "Could not fetch remote file list"
        return
    fi
    
    # Check each remote file
    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        
        local local_file="$remote_file"
        local will_update=false
        local status="unknown"
        
        # Check if this file should be updated
        if should_update_file "$remote_file"; then
            # Get remote content and compare
            local remote_content
            remote_content=$(fetch_github_file "$remote_file" "$UPSTREAM_BRANCH")
            if [[ $? -eq 0 ]]; then
                if [[ -f "$local_file" ]]; then
                    if compare_file_checksums "$local_file" "$remote_content"; then
                        status="unchanged"
                    else
                        status="changed"
                        will_update=true
                    fi
                else
                    status="new"
                    will_update=true
                fi
            else
                status="fetch_error"
            fi
        elif should_preserve_file "$remote_file"; then
            status="preserved"
        else
            status="ignored"
        fi
        
        # Show status
        case "$status" in
            "changed")
                log $GREEN "  ✅ $remote_file (will be updated - content changed)"
                ;;
            "new")
                log $GREEN "  ➕ $remote_file (will be added - new file)"
                ;;
            "unchanged")
                log $BLUE "  ➡️  $remote_file (up to date)"
                ;;
            "preserved")
                log $YELLOW "  🔒 $remote_file (preserved - no changes)"
                ;;
            "ignored")
                log $YELLOW "  ⏭️  $remote_file (ignored by configuration)"
                ;;
            "fetch_error")
                log $RED "  ❌ $remote_file (error fetching)"
                ;;
        esac
        
    done <<< "$remote_files"
}

# Show status summary
function show_status_summary() {
    compare_versions
    local version_result=$?
    
    if [[ "$QUIET" == true ]]; then
        case $version_result in
            0)
                echo "UPDATE_STATUS=up_to_date"
                echo "CURRENT_VERSION=$CURRENT_VERSION"
                echo "UPSTREAM_VERSION=$UPSTREAM_VERSION"
                ;;
            1)
                echo "UPDATE_STATUS=update_available"
                echo "CURRENT_VERSION=$CURRENT_VERSION"
                echo "UPSTREAM_VERSION=$UPSTREAM_VERSION"
                ;;
            -1)
                echo "UPDATE_STATUS=ahead"
                echo "CURRENT_VERSION=$CURRENT_VERSION"
                echo "UPSTREAM_VERSION=$UPSTREAM_VERSION"
                ;;
            2)
                echo "UPDATE_STATUS=unknown"
                echo "CURRENT_VERSION=$CURRENT_VERSION"
                echo "UPSTREAM_VERSION=$UPSTREAM_VERSION"
                ;;
        esac
        return $version_result
    fi
    
    header "\n📊 Update Status Summary:"
    
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
    if [[ "$QUIET" != true ]]; then
        header "🔍 Claude Code PM Update Check"
    fi
    
    validate_environment
    read_config
    get_version_info
    
    # Check if updates are available
    compare_versions
    local update_status=$?
    
    if [[ $update_status -eq 1 ]]; then
        # Updates available
        if [[ "$VERBOSE" == true ]]; then
            show_changes
        fi
        show_file_changes
    fi
    
    show_status_summary
    
    if [[ "$QUIET" != true ]]; then
        info "\nTo apply updates: /pm:update"
        info "To see more details: /pm:update --dry-run"
    fi
    
    # Record last check time
    echo "$(date +%s)" > "$PROJECT_ROOT/.claude/.last-update-check" 2>/dev/null || true
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi