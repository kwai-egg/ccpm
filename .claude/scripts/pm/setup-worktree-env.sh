#!/bin/bash
# Setup environment variable symlinks for git worktrees
# Usage: setup-worktree-env.sh [worktree_path] [main_repo_path]

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

# Setup environment variable symlinks for a specific worktree
setup_env_symlinks() {
    local worktree_path="$1"
    local main_repo="$2"
    
    debug_log "Setting up env symlinks for worktree: $worktree_path"
    debug_log "Main repo: $main_repo"
    
    # List of common env files to symlink
    local env_files=(".env" ".env.local" ".env.development" ".env.staging" ".env.production" ".env.test")
    local linked_count=0
    local skipped_count=0
    
    # Change to worktree directory
    local original_dir=$(pwd)
    cd "$worktree_path"
    
    for env_file in "${env_files[@]}"; do
        local main_env_file="$main_repo/$env_file"
        local worktree_env_file="$env_file"
        
        # Check if main repo has this env file
        if [[ ! -f "$main_env_file" ]]; then
            debug_log "Skipping $env_file (not found in main repo)"
            continue
        fi
        
        # Check if worktree already has this file
        if [[ -e "$worktree_env_file" ]]; then
            if [[ -L "$worktree_env_file" ]]; then
                local current_target
                current_target=$(readlink "$worktree_env_file")
                local expected_target
                expected_target=$(realpath "$main_env_file")
                
                if [[ "$current_target" == "$expected_target" ]]; then
                    debug_log "Symlink already correct: $env_file -> $main_env_file"
                    ((linked_count++))
                    continue
                else
                    info_log "Updating existing symlink for $env_file"
                    rm "$worktree_env_file"
                fi
            else
                info_log "File $env_file exists in worktree, backing up as ${env_file}.backup"
                mv "$worktree_env_file" "${worktree_env_file}.backup"
            fi
        fi
        
        # Create the symlink using absolute path
        local abs_main_env
        abs_main_env=$(realpath "$main_env_file")
        ln -s "$abs_main_env" "$worktree_env_file"
        info_log "✅ Created symlink: $env_file -> $abs_main_env"
        ((linked_count++))
    done
    
    # Return to original directory
    cd "$original_dir"
    
    # Summary
    if [[ $linked_count -gt 0 ]]; then
        info_log "Successfully linked $linked_count environment files"
    else
        info_log "No environment files found to link"
    fi
}

# Verify the setup works
verify_env_setup() {
    local worktree_path="$1"
    local original_dir=$(pwd)
    cd "$worktree_path"
    
    info_log "Verifying environment setup..."
    
    local env_found=false
    for env_file in .env .env.local .env.development; do
        if [[ -L "$env_file" ]]; then
            info_log "✅ $env_file symlink exists"
            env_found=true
        fi
    done
    
    if [[ "$env_found" == "false" ]]; then
        info_log "⚠️  No environment file symlinks found"
    fi
    
    # Check if we can read environment variables
    if [[ -f ".env" ]]; then
        local env_vars
        env_vars=$(grep -E "^[A-Z_]+" .env 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$env_vars" -gt 0 ]]; then
            info_log "✅ Found $env_vars environment variables in .env"
        else
            info_log "⚠️  No environment variables found in .env"
        fi
    fi
    
    cd "$original_dir"
}

main() {
    local target_path
    local main_repo_path
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        # No argument - use current directory and auto-detect main repo
        target_path="$(pwd)"
        debug_log "Using current directory: $target_path"
        
        # Try to find main repo automatically
        if ! main_repo_path=$(find_main_repo "$target_path"); then
            exit 1
        fi
    elif [[ $# -eq 1 ]]; then
        # Worktree path provided, auto-detect main repo
        target_path="$1"
        if [[ ! -d "$target_path" ]]; then
            error_log "Directory does not exist: $target_path"
            exit 1
        fi
        
        if ! main_repo_path=$(find_main_repo "$target_path"); then
            exit 1
        fi
    elif [[ $# -eq 2 ]]; then
        # Both paths provided
        target_path="$1"
        main_repo_path="$2"
        
        if [[ ! -d "$target_path" ]]; then
            error_log "Worktree directory does not exist: $target_path"
            exit 1
        fi
        
        if [[ ! -d "$main_repo_path" ]]; then
            error_log "Main repo directory does not exist: $main_repo_path"
            exit 1
        fi
    else
        error_log "Usage: $SCRIPT_NAME [worktree_path] [main_repo_path]"
        exit 1
    fi
    
    # Convert to absolute paths
    target_path=$(get_abs_path "$target_path")
    main_repo_path=$(get_abs_path "$main_repo_path")
    
    debug_log "Worktree: $target_path"
    debug_log "Main repository: $main_repo_path"
    
    # Setup the symlinks
    setup_env_symlinks "$target_path" "$main_repo_path"
    
    # Verify setup
    verify_env_setup "$target_path"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi