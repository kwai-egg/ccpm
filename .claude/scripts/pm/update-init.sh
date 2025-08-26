#!/bin/bash
# Script: update-init.sh
# Purpose: Initialize the Claude Code PM update system for an existing project
# Usage: ./update-init.sh [--upstream URL] [--branch BRANCH] [--force]

set -e  # Exit on error
set -u  # Error on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
CONFIG_FILE="$PROJECT_ROOT/.claude/.claude-pm.yaml"
VERSION_FILE="$PROJECT_ROOT/.claude/VERSION"

# Default values
DEFAULT_UPSTREAM="https://github.com/kwai-egg/ccpm.git"
DEFAULT_BRANCH="main"

# Parse command line arguments
UPSTREAM=""
BRANCH=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --upstream)
            UPSTREAM="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--upstream URL] [--branch BRANCH] [--force]"
            exit 1
            ;;
    esac
done

# Set defaults
UPSTREAM=${UPSTREAM:-$DEFAULT_UPSTREAM}
BRANCH=${BRANCH:-$DEFAULT_BRANCH}

# Source GitHub utilities for logging functions
source "$SCRIPT_DIR/github-utils.sh"

# Validate environment
function validate_environment() {
    # Change to project root if we can determine it
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        cd "$PROJECT_ROOT"
        CONFIG_FILE="$PROJECT_ROOT/.claude/.claude-pm.yaml"
        VERSION_FILE="$PROJECT_ROOT/.claude/VERSION"
    fi

    # Check if basic Claude Code PM structure exists
    if [[ ! -d ".claude" ]]; then
        error_exit "Claude Code PM not found. Install first from: https://github.com/kwai-egg/ccpm"
    fi

    # Check if already initialized (unless force)
    if [[ -f "$CONFIG_FILE" && "$FORCE" != true ]]; then
        error_exit "Update system already initialized. Use --force to reinitialize"
    fi
}

# Create configuration file
function create_configuration() {
    info "Creating configuration file: $CONFIG_FILE"
    info "  Upstream: $UPSTREAM"
    info "  Branch: $BRANCH"
    
    cat > "$CONFIG_FILE" << EOF
---
# Claude Code PM Update Configuration
version: 1.0
upstream: $UPSTREAM
branch: $BRANCH

# Files and directories to preserve during updates (project-specific data)
preserve:
  - ".claude/epics/"           # PM workspace with project epics
  - ".claude/prds/"            # Product Requirements Documents
  - ".claude/context/"         # Project context documentation
  - ".claude/CLAUDE.md"        # Project-specific Claude instructions
  - ".claude/**/*.local.*"     # Any .local files (settings, configs)
  - ".claude/settings.json"    # Local settings
  - ".claude/config.yaml"      # Local configuration
  - ".gitignore"              # Project gitignore (may have custom entries)
  - "README.md"               # Project README (may be customized)

# Files and directories to update from upstream (system components)
update:
  - ".claude/agents/"          # AI agent definitions
  - ".claude/commands/"        # Command specifications and implementations
  - ".claude/rules/"           # System operation rules and patterns
  - ".claude/scripts/"         # Automation and utility scripts
  - ".claude/templates/"       # Content templates and patterns
  - ".claude/VERSION"          # Version tracking
  - ".claude/CHANGELOG.md"     # System changelog
  - "AGENTS.md"               # Agent documentation
  - "COMMANDS.md"             # Command reference
  - "LICENSE"                 # License file
  - "screenshot.webp"         # Project screenshot

# Backup configuration
backup:
  enabled: true
  keep_backups: 5              # Number of file backups to retain
  backup_location: ".ccpm-backups/"

# Update behavior
update_behavior:
  check_uncommitted: false     # Optional warning for git changes
  create_backup: true          # Always create backup before update
  validate_after: true         # Run validation after update
  auto_cleanup: false          # Don't auto-delete backup directories

# Validation settings
validation:
  check_commands: true         # Verify command files are valid
  check_structure: true        # Verify directory structure
  check_dependencies: true     # Verify required tools are available
  check_files: true            # Verify critical files exist after update
EOF

    success "Configuration file created"
}

# Setup directory structure
function setup_directories() {
    info "Setting up directory structure"
    
    # Create backup directory
    mkdir -p ".ccpm-backups"
    success "Backup directory created: .ccpm-backups/"
    
    # Add to .gitignore if not already present
    if [[ -f ".gitignore" ]]; then
        if ! grep -q ".ccpm-backups" ".gitignore" 2>/dev/null; then
            info "Adding backup directory to .gitignore"
            echo "" >> ".gitignore"
            echo "# Claude Code PM Update System" >> ".gitignore"
            echo ".ccpm-backups/" >> ".gitignore"
            echo ".claude/.last-update-check" >> ".gitignore"
        fi
    else
        info "Creating .gitignore with backup directory"
        cat > ".gitignore" << EOF
# Claude Code PM Update System
.ccmp-backups/
.claude/.last-update-check
EOF
    fi
}

# Setup version tracking
function setup_version_tracking() {
    info "Setting up version tracking"
    
    # Create version file if missing
    if [[ ! -f "$VERSION_FILE" ]]; then
        echo "1.0.0" > "$VERSION_FILE"
        success "Created version file: .claude/VERSION"
    else
        local current_version=$(cat "$VERSION_FILE")
        info "Current version: $current_version"
    fi
    
    # Create changelog if missing
    if [[ ! -f ".claude/CHANGELOG.md" ]]; then
        cat > ".claude/CHANGELOG.md" << EOF
---
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
version: 1.0
author: Claude Code PM System
---

# Claude Code PM Changelog

## [1.0.0] - $(date -u +"%Y-%m-%d")

### Added
- Initial Claude Code PM system installation
- Project-specific implementation and customizations

### Notes
- This project has been set up with Claude Code PM update system
- Run '/pm:update-check' to check for available updates
- Run '/pm:update' to apply updates while preserving project data
EOF
        success "Created changelog file: .claude/CHANGELOG.md"
    fi
}

# Test upstream connectivity
function test_upstream() {
    info "Testing upstream connectivity..."
    
    # Initialize GitHub utilities
    init_github_utils "$UPSTREAM" "$BRANCH"
    
    # Try to fetch version from upstream
    local upstream_version
    upstream_version=$(get_remote_version "$BRANCH" 2>/dev/null)
    if [[ $? -eq 0 && -n "$upstream_version" ]]; then
        success "Upstream accessible - version: $upstream_version"
    else
        warning "Upstream not accessible (network issue or authentication required)"
        info "Update system will still work, but you may need to check connectivity"
    fi
}

# Run initial system check
function initial_system_check() {
    info "Running initial system check..."
    
    # Run update check to see current status
    if [[ -x "$SCRIPT_DIR/update-check.sh" ]]; then
        "$SCRIPT_DIR/update-check.sh" --quiet || true
        success "Initial system check completed"
    else
        warning "Update check script not found - basic setup complete"
    fi
}

# Show usage instructions
function show_instructions() {
    header "\n📚 Claude Code PM Update System Ready!"
    info ""
    info "Next Steps:"
    info ""
    info "1. Check for updates:"
    info "   /pm:update-check"
    info ""
    info "2. View system status:"
    info "   /pm:update-status"
    info ""
    info "3. Apply updates (when available):"
    info "   /pm:update"
    info ""
    info "4. For help with update commands:"
    info "   /pm:help | grep update"
    info ""
    info "📝 Configuration saved to: .claude/.claude-pm.yaml"
    info "💾 Backups will be stored in: .ccpm-backups/"
    info ""
    info "🔧 To customize settings, edit .claude/.claude-pm.yaml"
    info "🔗 Upstream: $UPSTREAM (branch: $BRANCH)"
}

# Main execution
function main() {
    header "🚀 Initializing Claude Code PM Update System"
    info ""
    
    validate_environment
    create_configuration
    setup_directories
    setup_version_tracking
    test_upstream
    initial_system_check
    show_instructions
    
    success "\n✅ Update system initialization complete!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi