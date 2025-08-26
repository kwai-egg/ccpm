#!/bin/bash
# Script: push.sh
# Purpose: Bump version and commit/push changes
# Usage: ./push.sh [commit-message]

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/path-resolver.sh"

VERSION_FILE="$CLAUDE_DIR/VERSION"
COMMIT_MESSAGE="${1:-Auto-bump version and push changes}"

# Function to increment version
increment_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        local current_version=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
        local new_version
        
        # Simple increment: if it's a number, add 0.1, otherwise append .1
        if [[ "$current_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
            # It's a version number, increment the last part
            local base_version=$(echo "$current_version" | sed 's/\.[0-9]*$//')
            local last_part=$(echo "$current_version" | sed 's/.*\.//')
            if [[ "$current_version" == "$last_part" ]]; then
                # No dots, just increment
                new_version=$((current_version + 1))
            else
                # Has dots, increment last part
                new_version="$base_version.$((last_part + 1))"
            fi
        else
            # Not a standard version, just append .1
            new_version="$current_version.1"
        fi
        
        echo "$new_version" > "$VERSION_FILE"
        echo "Version bumped: $current_version → $new_version"
    else
        echo "1.0" > "$VERSION_FILE"
        echo "Version initialized: 1.0"
    fi
}

# Main execution
echo "🚀 Push with Version Bump"
echo "========================="

# Bump version
increment_version

# Add all changes
git add .

# Commit with message
git commit -m "$COMMIT_MESSAGE

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to remote
git push

echo "✅ Successfully pushed changes with version bump!"