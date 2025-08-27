#!/bin/bash
# Project-scoped dependency cache management for git worktrees
# Prevents cross-project contamination and handles dependency changes

set -e

SCRIPT_NAME="$(basename "$0")"
DEBUG_MODE="${CLAUDE_HOOK_DEBUG:-false}"
CACHE_BASE="$HOME/.cache/ccpm-node-modules"
LOCK_DIR="$CACHE_BASE/locks"
CACHE_RETENTION_DAYS=30

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

# Initialize cache directories
init_cache_dirs() {
    mkdir -p "$CACHE_BASE"
    mkdir -p "$LOCK_DIR"
    debug_log "Initialized cache directories"
}

# Get project name from directory or git remote
get_project_name() {
    local repo_path="$1"
    local project_name
    
    # Try to get from git remote first
    if cd "$repo_path" 2>/dev/null && git remote get-url origin &>/dev/null; then
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            # Extract repo name from URL (handles both SSH and HTTPS)
            project_name=$(basename "$remote_url" .git)
        fi
    fi
    
    # Fallback to directory name
    if [[ -z "$project_name" ]]; then
        project_name=$(basename "$repo_path")
    fi
    
    # Sanitize project name (replace special chars with dash)
    project_name=$(echo "$project_name" | sed 's/[^a-zA-Z0-9._-]/-/g')
    echo "$project_name"
}

# Generate hash from package files
get_package_hash() {
    local repo_path="$1"
    local hash_input=""
    
    # Include package.json (required)
    if [[ -f "$repo_path/package.json" ]]; then
        hash_input+=$(cat "$repo_path/package.json")
    else
        error_log "No package.json found in: $repo_path"
        return 1
    fi
    
    # Include package-lock.json if exists
    if [[ -f "$repo_path/package-lock.json" ]]; then
        hash_input+=$(cat "$repo_path/package-lock.json")
    fi
    
    # Include yarn.lock if exists
    if [[ -f "$repo_path/yarn.lock" ]]; then
        hash_input+=$(cat "$repo_path/yarn.lock")
    fi
    
    # Generate hash and take first 8 characters
    echo -n "$hash_input" | md5sum | cut -c1-8
}

# Get cache path for project and hash
get_cache_path() {
    local project_name="$1"
    local package_hash="$2"
    echo "$CACHE_BASE/project-${project_name}-${package_hash}"
}

# Get lock file path
get_lock_path() {
    local project_name="$1"
    local package_hash="$2"
    echo "$LOCK_DIR/${project_name}-${package_hash}.lock"
}

# Acquire file lock with timeout
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-300}"  # 5 minutes default
    local count=0
    
    debug_log "Acquiring lock: $lock_file"
    
    while [[ $count -lt $timeout ]]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            debug_log "Lock acquired: $lock_file"
            return 0
        fi
        
        # Check if lock is stale (older than 10 minutes)
        if [[ -f "$lock_file" ]]; then
            local lock_age
            lock_age=$(($(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || echo 0)))
            if [[ $lock_age -gt 600 ]]; then
                info_log "Removing stale lock (${lock_age}s old)"
                rm -f "$lock_file"
                continue
            fi
        fi
        
        sleep 1
        ((count++))
    done
    
    error_log "Failed to acquire lock after ${timeout}s: $lock_file"
    return 1
}

# Release file lock
release_lock() {
    local lock_file="$1"
    rm -f "$lock_file"
    debug_log "Released lock: $lock_file"
}

# Install dependencies to cache
install_to_cache() {
    local repo_path="$1"
    local cache_path="$2"
    local lock_file="$3"
    
    info_log "Installing dependencies to cache: $cache_path"
    
    # Create cache directory
    mkdir -p "$cache_path"
    
    # Copy package files to cache
    cp "$repo_path/package.json" "$cache_path/"
    [[ -f "$repo_path/package-lock.json" ]] && cp "$repo_path/package-lock.json" "$cache_path/"
    [[ -f "$repo_path/yarn.lock" ]] && cp "$repo_path/yarn.lock" "$cache_path/"
    
    # Install in cache directory
    cd "$cache_path"
    
    # Determine package manager
    local npm_cmd="npm"
    if [[ -f "yarn.lock" ]]; then
        npm_cmd="yarn"
    elif [[ -f "pnpm-lock.yaml" ]]; then
        npm_cmd="pnpm"
    fi
    
    info_log "Running: $npm_cmd install"
    if $npm_cmd install; then
        info_log "✅ Dependencies installed successfully to cache"
        return 0
    else
        error_log "Failed to install dependencies to cache"
        rm -rf "$cache_path"
        return 1
    fi
}

# Create symlink from cache to worktree
link_from_cache() {
    local cache_path="$1"
    local worktree_path="$2"
    local worktree_node_modules="$worktree_path/node_modules"
    local cache_node_modules="$cache_path/node_modules"
    
    # Verify cache has node_modules
    if [[ ! -d "$cache_node_modules" ]]; then
        error_log "Cache missing node_modules: $cache_node_modules"
        return 1
    fi
    
    # Remove existing node_modules in worktree
    if [[ -e "$worktree_node_modules" ]]; then
        if [[ -L "$worktree_node_modules" ]]; then
            debug_log "Removing existing symlink: $worktree_node_modules"
            rm "$worktree_node_modules"
        else
            info_log "Backing up existing node_modules as node_modules.backup"
            mv "$worktree_node_modules" "${worktree_node_modules}.backup"
        fi
    fi
    
    # Create symlink
    ln -s "$cache_node_modules" "$worktree_node_modules"
    info_log "✅ Linked: $worktree_node_modules -> $cache_node_modules"
}

# Check if worktree has different dependencies than main
compare_package_files() {
    local main_repo="$1"
    local worktree_path="$2"
    
    # Compare package.json
    if [[ -f "$main_repo/package.json" && -f "$worktree_path/package.json" ]]; then
        if ! cmp -s "$main_repo/package.json" "$worktree_path/package.json"; then
            return 1  # Different
        fi
    fi
    
    # Compare package-lock.json if both exist
    if [[ -f "$main_repo/package-lock.json" && -f "$worktree_path/package-lock.json" ]]; then
        if ! cmp -s "$main_repo/package-lock.json" "$worktree_path/package-lock.json"; then
            return 1  # Different
        fi
    fi
    
    return 0  # Same
}

# Setup cached dependencies for worktree
setup_cached_dependencies() {
    local main_repo="$1"
    local worktree_path="$2"
    
    init_cache_dirs
    
    # Get project info
    local project_name
    project_name=$(get_project_name "$main_repo")
    
    # Determine which package files to use (worktree if different, else main)
    local package_source="$main_repo"
    local use_worktree_deps=false
    
    if compare_package_files "$main_repo" "$worktree_path"; then
        debug_log "Dependencies match main repo"
        package_source="$main_repo"
    else
        info_log "Worktree has different dependencies than main repo"
        package_source="$worktree_path"
        use_worktree_deps=true
    fi
    
    # Get package hash
    local package_hash
    if ! package_hash=$(get_package_hash "$package_source"); then
        return 1
    fi
    
    debug_log "Project: $project_name, Hash: $package_hash"
    
    # Get cache and lock paths
    local cache_path
    cache_path=$(get_cache_path "$project_name" "$package_hash")
    local lock_file
    lock_file=$(get_lock_path "$project_name" "$package_hash")
    
    # Check if cache already exists
    if [[ -d "$cache_path/node_modules" ]]; then
        info_log "Using existing cached dependencies: $cache_path"
        link_from_cache "$cache_path" "$worktree_path"
        return 0
    fi
    
    # Need to install - acquire lock
    if ! acquire_lock "$lock_file"; then
        return 1
    fi
    
    # Double-check cache doesn't exist (race condition protection)
    if [[ -d "$cache_path/node_modules" ]]; then
        info_log "Cache created while waiting for lock: $cache_path"
        release_lock "$lock_file"
        link_from_cache "$cache_path" "$worktree_path"
        return 0
    fi
    
    # Install to cache
    if install_to_cache "$package_source" "$cache_path" "$lock_file"; then
        release_lock "$lock_file"
        link_from_cache "$cache_path" "$worktree_path"
        
        # Clean up old caches
        cleanup_old_caches "$project_name"
        
        if [[ "$use_worktree_deps" == "true" ]]; then
            info_log "💡 Worktree is using different dependencies than main repo"
            info_log "    To sync these changes to main, run:"
            info_log "    bash ~/.claude/scripts/pm/sync-dependencies.sh"
        fi
        
        return 0
    else
        release_lock "$lock_file"
        return 1
    fi
}

# Clean up old unused caches
cleanup_old_caches() {
    local project_name="$1"
    local cutoff_date
    cutoff_date=$(date -d "${CACHE_RETENTION_DAYS} days ago" +%s 2>/dev/null || date -v-${CACHE_RETENTION_DAYS}d +%s)
    
    debug_log "Cleaning up caches older than $CACHE_RETENTION_DAYS days for project: $project_name"
    
    find "$CACHE_BASE" -maxdepth 1 -name "project-${project_name}-*" -type d | while read -r cache_dir; do
        if [[ -d "$cache_dir" ]]; then
            local cache_age
            cache_age=$(stat -f %m "$cache_dir" 2>/dev/null || echo 0)
            if [[ $cache_age -lt $cutoff_date ]]; then
                info_log "Removing old cache: $(basename "$cache_dir")"
                rm -rf "$cache_dir"
            fi
        fi
    done
}

# List all caches for a project
list_caches() {
    local project_name="$1"
    
    info_log "Cached dependencies for project: $project_name"
    find "$CACHE_BASE" -maxdepth 1 -name "project-${project_name}-*" -type d | while read -r cache_dir; do
        if [[ -d "$cache_dir/node_modules" ]]; then
            local cache_name
            cache_name=$(basename "$cache_dir")
            local cache_age
            cache_age=$(stat -f %m "$cache_dir" 2>/dev/null || echo 0)
            local age_days
            age_days=$(( ($(date +%s) - cache_age) / 86400 ))
            echo "  ✅ $cache_name (${age_days} days old)"
        fi
    done
}

# Main function
main() {
    local command="${1:-setup}"
    shift
    
    case "$command" in
        "setup")
            if [[ $# -ne 2 ]]; then
                error_log "Usage: $SCRIPT_NAME setup <main_repo_path> <worktree_path>"
                exit 1
            fi
            setup_cached_dependencies "$1" "$2"
            ;;
        "list")
            if [[ $# -ne 1 ]]; then
                error_log "Usage: $SCRIPT_NAME list <project_name>"
                exit 1
            fi
            list_caches "$1"
            ;;
        "cleanup")
            if [[ $# -ne 1 ]]; then
                error_log "Usage: $SCRIPT_NAME cleanup <project_name>"
                exit 1
            fi
            cleanup_old_caches "$1"
            ;;
        "hash")
            if [[ $# -ne 1 ]]; then
                error_log "Usage: $SCRIPT_NAME hash <repo_path>"
                exit 1
            fi
            get_package_hash "$1"
            ;;
        *)
            error_log "Unknown command: $command"
            error_log "Available commands: setup, list, cleanup, hash"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi