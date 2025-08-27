#!/bin/bash
# Setup node_modules symlink for git worktrees
# Usage: setup-worktree-deps.sh [worktree_path]

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

# Setup symlink for a specific worktree
setup_worktree_symlink() {
    local worktree_path="$1"
    local main_repo="$2"
    
    debug_log "Setting up symlink for worktree: $worktree_path"
    debug_log "Main repo: $main_repo"
    
    # Check if main repo has package.json
    if [[ ! -f "$main_repo/package.json" ]]; then
        debug_log "No package.json in main repo, skipping"
        return 0
    fi
    
    # Check if main repo has node_modules
    if [[ ! -d "$main_repo/node_modules" ]]; then
        info_log "Main repo has no node_modules directory"
        info_log "Run 'npm install' in main repo first: $main_repo"
        return 1
    fi
    
    local worktree_node_modules="$worktree_path/node_modules"
    local main_node_modules="$main_repo/node_modules"
    
    # If worktree already has node_modules, check what it is
    if [[ -e "$worktree_node_modules" ]]; then
        if [[ -L "$worktree_node_modules" ]]; then
            local current_target
            current_target=$(readlink "$worktree_node_modules")
            if [[ "$current_target" == "$main_node_modules" ]]; then
                info_log "Symlink already correct: $worktree_node_modules -> $main_node_modules"
                return 0
            else
                info_log "Updating existing symlink target"
                rm "$worktree_node_modules"
            fi
        else
            # Check if worktree has different package.json
            if [[ -f "$worktree_path/package.json" ]] && ! cmp -s "$main_repo/package.json" "$worktree_path/package.json"; then
                info_log "Worktree has different package.json, keeping separate node_modules"
                return 0
            fi
            
            info_log "Replacing existing node_modules directory with symlink"
            rm -rf "$worktree_node_modules"
        fi
    fi
    
    # Create the symlink
    ln -s "$main_node_modules" "$worktree_node_modules"
    info_log "✅ Created symlink: $worktree_node_modules -> $main_node_modules"
}

main() {
    local target_path
    
    # Determine target path
    if [[ $# -eq 0 ]]; then
        # No argument - use current directory
        target_path="$(pwd)"
        debug_log "Using current directory: $target_path"
    elif [[ $# -eq 1 ]]; then
        # Path argument provided
        target_path="$1"
        if [[ ! -d "$target_path" ]]; then
            error_log "Directory does not exist: $target_path"
            exit 1
        fi
    else
        error_log "Usage: $SCRIPT_NAME [worktree_path]"
        exit 1
    fi
    
    # Convert to absolute path
    target_path=$(get_abs_path "$target_path")
    
    # Find main repository
    local main_repo
    if ! main_repo=$(find_main_repo "$target_path"); then
        exit 1
    fi
    
    debug_log "Main repository: $main_repo"
    
    # Setup the node_modules symlink
    setup_worktree_symlink "$target_path" "$main_repo"
    
    # Setup environment variable symlinks
    info_log "Setting up environment variables..."
    bash ~/.claude/scripts/pm/setup-worktree-env.sh "$target_path" "$main_repo"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi