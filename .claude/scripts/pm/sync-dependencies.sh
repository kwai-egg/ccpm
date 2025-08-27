#!/bin/bash
# Sync dependencies from worktree back to main repository
# Handles cases where feature branches add/modify dependencies

set -e

SCRIPT_NAME="$(basename "$0")"
DEBUG_MODE="${CLAUDE_HOOK_DEBUG:-false}"

debug_log() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "DEBUG [$SCRIPT_NAME]: $*" >&2
    fi
}

info_log() {
    echo "[$SCRIPT_NAME]: $*"
}

error_log() {
    echo "ERROR [$SCRIPT_NAME]: $*" >&2
}

warning_log() {
    echo "WARNING [$SCRIPT_NAME]: $*" >&2
}

# Get the absolute path of a directory
get_abs_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    else
        echo "$path"
    fi
}

# Find the main repository root from a worktree
find_main_repo() {
    local worktree_path="$1"
    
    if [[ ! -f "$worktree_path/.git" ]]; then
        error_log "Not a worktree: $worktree_path (no .git file)"
        return 1
    fi
    
    # Read the gitdir from .git file
    local gitdir_content
    gitdir_content=$(cat "$worktree_path/.git" 2>/dev/null | tr -d '\r')
    
    if [[ ! "$gitdir_content" =~ ^gitdir:[[:space:]]*(.*) ]]; then
        error_log "Invalid .git file format in: $worktree_path"
        return 1
    fi
    
    local gitdir_path="${BASH_REMATCH[1]}"
    debug_log "Found gitdir: $gitdir_path"
    
    # Make gitdir absolute if relative
    if [[ ! "$gitdir_path" =~ ^/ ]]; then
        gitdir_path="$worktree_path/$gitdir_path"
    fi
    
    # Check if this is a worktree gitdir
    if [[ ! "$gitdir_path" =~ /worktrees/ ]]; then
        error_log "Not a linked worktree: $worktree_path"
        return 1
    fi
    
    # Find main repo by going up from gitdir
    local main_gitdir
    main_gitdir=$(dirname "$(dirname "$gitdir_path")")
    
    # The main repo is the parent of the .git directory
    local main_repo
    main_repo=$(dirname "$main_gitdir")
    
    if [[ ! -d "$main_repo" ]]; then
        error_log "Cannot find main repository from: $gitdir_path"
        return 1
    fi
    
    get_abs_path "$main_repo"
}

# Compare package files and show differences
compare_and_show_diff() {
    local main_repo="$1"
    local worktree_path="$2"
    local has_differences=false
    
    info_log "Comparing dependency files between worktree and main repo..."
    
    # Compare package.json
    if [[ -f "$main_repo/package.json" && -f "$worktree_path/package.json" ]]; then
        if ! cmp -s "$main_repo/package.json" "$worktree_path/package.json"; then
            info_log "📦 package.json has differences:"
            echo
            diff -u "$main_repo/package.json" "$worktree_path/package.json" || true
            echo
            has_differences=true
        else
            info_log "✅ package.json is identical"
        fi
    elif [[ -f "$worktree_path/package.json" ]]; then
        warning_log "Main repo missing package.json, but worktree has one"
        has_differences=true
    fi
    
    # Compare package-lock.json
    if [[ -f "$main_repo/package-lock.json" && -f "$worktree_path/package-lock.json" ]]; then
        if ! cmp -s "$main_repo/package-lock.json" "$worktree_path/package-lock.json"; then
            info_log "🔒 package-lock.json has differences"
            has_differences=true
        else
            info_log "✅ package-lock.json is identical"
        fi
    elif [[ -f "$worktree_path/package-lock.json" && ! -f "$main_repo/package-lock.json" ]]; then
        info_log "📦 Worktree has package-lock.json, but main repo doesn't"
        has_differences=true
    fi
    
    # Compare yarn.lock if present
    if [[ -f "$worktree_path/yarn.lock" ]]; then
        if [[ -f "$main_repo/yarn.lock" ]]; then
            if ! cmp -s "$main_repo/yarn.lock" "$worktree_path/yarn.lock"; then
                info_log "🧶 yarn.lock has differences"
                has_differences=true
            else
                info_log "✅ yarn.lock is identical"
            fi
        else
            info_log "📦 Worktree has yarn.lock, but main repo doesn't"
            has_differences=true
        fi
    fi
    
    return $([ "$has_differences" = true ] && echo 1 || echo 0)
}

# Backup files before sync
backup_main_files() {
    local main_repo="$1"
    local backup_suffix="backup-$(date +%Y%m%d-%H%M%S)"
    
    info_log "Creating backup of main repo dependency files..."
    
    if [[ -f "$main_repo/package.json" ]]; then
        cp "$main_repo/package.json" "$main_repo/package.json.$backup_suffix"
        debug_log "Backed up package.json"
    fi
    
    if [[ -f "$main_repo/package-lock.json" ]]; then
        cp "$main_repo/package-lock.json" "$main_repo/package-lock.json.$backup_suffix"
        debug_log "Backed up package-lock.json"
    fi
    
    if [[ -f "$main_repo/yarn.lock" ]]; then
        cp "$main_repo/yarn.lock" "$main_repo/yarn.lock.$backup_suffix"
        debug_log "Backed up yarn.lock"
    fi
    
    echo "$backup_suffix"
}

# Sync dependency files from worktree to main
sync_dependency_files() {
    local main_repo="$1"
    local worktree_path="$2"
    local backup_suffix="$3"
    
    info_log "Syncing dependency files from worktree to main repo..."
    
    # Sync package.json
    if [[ -f "$worktree_path/package.json" ]]; then
        cp "$worktree_path/package.json" "$main_repo/package.json"
        info_log "✅ Synced package.json"
    fi
    
    # Sync package-lock.json
    if [[ -f "$worktree_path/package-lock.json" ]]; then
        cp "$worktree_path/package-lock.json" "$main_repo/package-lock.json"
        info_log "✅ Synced package-lock.json"
    fi
    
    # Sync yarn.lock
    if [[ -f "$worktree_path/yarn.lock" ]]; then
        cp "$worktree_path/yarn.lock" "$main_repo/yarn.lock"
        info_log "✅ Synced yarn.lock"
    fi
    
    info_log "Dependency files synced successfully"
    info_log "Backup files created with suffix: $backup_suffix"
}

# Install dependencies in main repo after sync
install_in_main() {
    local main_repo="$1"
    local original_dir=$(pwd)
    
    info_log "Installing dependencies in main repository..."
    cd "$main_repo"
    
    # Determine package manager
    local npm_cmd="npm"
    if [[ -f "yarn.lock" ]]; then
        npm_cmd="yarn"
    elif [[ -f "pnpm-lock.yaml" ]]; then
        npm_cmd="pnpm"
    fi
    
    info_log "Running: $npm_cmd install"
    if $npm_cmd install; then
        info_log "✅ Dependencies installed successfully in main repo"
        cd "$original_dir"
        return 0
    else
        error_log "Failed to install dependencies in main repo"
        cd "$original_dir"
        return 1
    fi
}

# Update other worktrees that use cached dependencies
update_cached_worktrees() {
    local main_repo="$1"
    
    info_log "Updating cached dependencies for other worktrees..."
    
    # Get project name for cache management
    local project_name
    project_name=$(basename "$main_repo")
    project_name=$(echo "$project_name" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # Force cache refresh by cleaning old caches
    bash ~/.claude/scripts/pm/dependency-cache.sh cleanup "$project_name"
    
    info_log "Old dependency caches cleared"
    info_log "Other worktrees will get updated dependencies on next run"
}

# Interactive confirmation
confirm_sync() {
    local main_repo="$1"
    local worktree_path="$2"
    
    echo
    info_log "🔄 Ready to sync dependencies:"
    info_log "   From: $worktree_path"
    info_log "   To:   $main_repo"
    echo
    warning_log "This will:"
    warning_log "  1. Backup existing main repo dependency files"
    warning_log "  2. Copy worktree dependency files to main repo"
    warning_log "  3. Run npm install in main repo"
    warning_log "  4. Clear cached dependencies for other worktrees"
    echo
    
    read -p "Continue with sync? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info_log "Sync cancelled by user"
        return 1
    fi
    
    return 0
}

# Main sync function
sync_dependencies() {
    local worktree_path="$1"
    local main_repo
    
    # Find main repository
    if ! main_repo=$(find_main_repo "$worktree_path"); then
        exit 1
    fi
    
    debug_log "Worktree: $worktree_path"
    debug_log "Main repo: $main_repo"
    
    # Check for differences
    if compare_and_show_diff "$main_repo" "$worktree_path"; then
        info_log "✅ No differences found - sync not needed"
        return 0
    fi
    
    # Confirm sync
    if ! confirm_sync "$main_repo" "$worktree_path"; then
        return 1
    fi
    
    # Backup existing files
    local backup_suffix
    backup_suffix=$(backup_main_files "$main_repo")
    
    # Sync files
    if ! sync_dependency_files "$main_repo" "$worktree_path" "$backup_suffix"; then
        error_log "Failed to sync dependency files"
        return 1
    fi
    
    # Install dependencies in main
    if ! install_in_main "$main_repo"; then
        error_log "Failed to install dependencies in main repo"
        warning_log "You may need to restore backup files manually"
        return 1
    fi
    
    # Update cached dependencies
    update_cached_worktrees "$main_repo"
    
    echo
    info_log "🎉 Dependency sync completed successfully!"
    info_log "All worktrees will use the updated dependencies on next setup"
    echo
}

# Show current status
show_status() {
    local worktree_path="$1"
    local main_repo
    
    # Find main repository
    if ! main_repo=$(find_main_repo "$worktree_path"); then
        exit 1
    fi
    
    info_log "Dependency status for:"
    info_log "  Worktree: $worktree_path"
    info_log "  Main repo: $main_repo"
    echo
    
    if compare_and_show_diff "$main_repo" "$worktree_path"; then
        info_log "✅ Worktree and main repo dependencies are synchronized"
    else
        warning_log "⚠️  Worktree has different dependencies than main repo"
        info_log "Run 'bash ~/.claude/scripts/pm/sync-dependencies.sh sync' to synchronize"
    fi
}

# Main function
main() {
    local command="${1:-sync}"
    local target_path
    
    # Determine target path
    if [[ $# -le 1 ]]; then
        # Use current directory
        target_path="$(pwd)"
        debug_log "Using current directory: $target_path"
    else
        # Path argument provided
        target_path="$2"
        if [[ ! -d "$target_path" ]]; then
            error_log "Directory does not exist: $target_path"
            exit 1
        fi
    fi
    
    # Convert to absolute path
    target_path=$(get_abs_path "$target_path")
    
    case "$command" in
        "sync")
            sync_dependencies "$target_path"
            ;;
        "status")
            show_status "$target_path"
            ;;
        "diff")
            local main_repo
            if main_repo=$(find_main_repo "$target_path"); then
                compare_and_show_diff "$main_repo" "$target_path"
            fi
            ;;
        *)
            error_log "Unknown command: $command"
            error_log "Available commands: sync, status, diff"
            error_log "Usage: $SCRIPT_NAME [sync|status|diff] [worktree_path]"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi