#!/bin/bash
# Script: memory-env.sh
# Purpose: Set up memory-optimized environment variables for Claude Code PM
# Usage: source ./memory-env.sh [coordinator|agent|reset]

# Configuration file path
CONFIG_FILE="~/.claude/.claude-pm.yaml"

# Function to parse YAML configuration
function get_config_value() {
    local key="$1"
    local default="$2"
    
    if [ -f "$CONFIG_FILE" ]; then
        # Extract value and remove comments
        grep "^  $key:" "$CONFIG_FILE" 2>/dev/null | cut -d':' -f2 | cut -d'#' -f1 | xargs || echo "$default"
    else
        echo "$default"
    fi
}

# Function to set coordinator environment
function set_coordinator_env() {
    local coordinator_heap=$(get_config_value "coordinator_heap_size" "16384")
    local gc_exposure=$(get_config_value "gc_exposure" "true")
    local optimize_for_size=$(get_config_value "optimize_for_size" "true")
    
    # Base NODE_OPTIONS
    local node_options="--max-old-space-size=$coordinator_heap"
    
    # Add garbage collection exposure if enabled
    if [ "$gc_exposure" = "true" ]; then
        node_options="$node_options --expose-gc"
    fi
    
    # Add size optimization if enabled
    if [ "$optimize_for_size" = "true" ]; then
        node_options="$node_options --optimize_for_size"
    fi
    
    # Add additional V8 flags for memory management
    node_options="$node_options --initial-old-space-size=1024"
    node_options="$node_options --max-semi-space-size=128"
    
    export NODE_OPTIONS="$node_options"
    export CLAUDE_PM_ROLE="coordinator"
    export CLAUDE_PM_MEMORY_LIMIT="${coordinator_heap}"
    
    echo "Coordinator environment configured:"
    echo "  NODE_OPTIONS: $NODE_OPTIONS"
    echo "  CLAUDE_PM_ROLE: $CLAUDE_PM_ROLE"
    echo "  CLAUDE_PM_MEMORY_LIMIT: $CLAUDE_PM_MEMORY_LIMIT MB"
}

# Function to set agent environment
function set_agent_env() {
    local agent_heap=$(get_config_value "agent_heap_size" "8192")
    local gc_exposure=$(get_config_value "gc_exposure" "true")
    local optimize_for_size=$(get_config_value "optimize_for_size" "true")
    
    # Base NODE_OPTIONS
    local node_options="--max-old-space-size=$agent_heap"
    
    # Add garbage collection exposure if enabled
    if [ "$gc_exposure" = "true" ]; then
        node_options="$node_options --expose-gc"
    fi
    
    # Add size optimization if enabled
    if [ "$optimize_for_size" = "true" ]; then
        node_options="$node_options --optimize_for_size"
    fi
    
    # Add additional V8 flags optimized for agents
    node_options="$node_options --initial-old-space-size=512"
    node_options="$node_options --max-semi-space-size=64"
    node_options="$node_options --no-lazy"
    
    export NODE_OPTIONS="$node_options"
    export CLAUDE_PM_ROLE="agent"
    export CLAUDE_PM_MEMORY_LIMIT="${agent_heap}"
    
    echo "Agent environment configured:"
    echo "  NODE_OPTIONS: $NODE_OPTIONS"
    echo "  CLAUDE_PM_ROLE: $CLAUDE_PM_ROLE"
    echo "  CLAUDE_PM_MEMORY_LIMIT: $CLAUDE_PM_MEMORY_LIMIT MB"
}

# Function to reset environment
function reset_env() {
    unset NODE_OPTIONS
    unset CLAUDE_PM_ROLE
    unset CLAUDE_PM_MEMORY_LIMIT
    
    echo "Memory environment reset"
}

# Function to show current environment
function show_env() {
    echo "Current Memory Environment:"
    echo "========================="
    echo "NODE_OPTIONS: ${NODE_OPTIONS:-<not set>}"
    echo "CLAUDE_PM_ROLE: ${CLAUDE_PM_ROLE:-<not set>}"
    echo "CLAUDE_PM_MEMORY_LIMIT: ${CLAUDE_PM_MEMORY_LIMIT:-<not set>}"
    
    # Show memory configuration from file
    echo ""
    echo "Configuration File Settings:"
    echo "============================"
    echo "Coordinator Heap: $(get_config_value "coordinator_heap_size" "16384") MB"
    echo "Agent Heap: $(get_config_value "agent_heap_size" "8192") MB"
    echo "GC Exposure: $(get_config_value "gc_exposure" "true")"
    echo "Optimize for Size: $(get_config_value "optimize_for_size" "true")"
}

# Function to create environment files for process spawning
function create_env_files() {
    local env_dir=".claude/env"
    mkdir -p "$env_dir"
    
    # Create coordinator environment file
    set_coordinator_env > /dev/null
    cat > "$env_dir/coordinator.env" << EOF
NODE_OPTIONS=$NODE_OPTIONS
CLAUDE_PM_ROLE=coordinator
CLAUDE_PM_MEMORY_LIMIT=$CLAUDE_PM_MEMORY_LIMIT
EOF
    
    # Create agent environment file
    set_agent_env > /dev/null
    cat > "$env_dir/agent.env" << EOF
NODE_OPTIONS=$NODE_OPTIONS
CLAUDE_PM_ROLE=agent
CLAUDE_PM_MEMORY_LIMIT=$CLAUDE_PM_MEMORY_LIMIT
EOF
    
    echo "Environment files created:"
    echo "  $env_dir/coordinator.env"
    echo "  $env_dir/agent.env"
}

# Function to apply environment from file
function apply_env_file() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        echo "❌ Environment file not found: $env_file"
        return 1
    fi
    
    source "$env_file"
    echo "✅ Applied environment from: $env_file"
}

# Main execution
function main() {
    local action="${1:-show}"
    
    case "$action" in
        "coordinator")
            set_coordinator_env
            ;;
        "agent")
            set_agent_env
            ;;
        "reset")
            reset_env
            ;;
        "show")
            show_env
            ;;
        "create-files")
            create_env_files
            ;;
        "apply")
            local env_file="${2:-}"
            if [ -z "$env_file" ]; then
                echo "Usage: $0 apply <env-file>"
                exit 1
            fi
            apply_env_file "$env_file"
            ;;
        *)
            echo "Usage: source $0 [coordinator|agent|reset|show|create-files|apply]"
            echo ""
            echo "Commands:"
            echo "  coordinator  - Set environment for coordinator process"
            echo "  agent        - Set environment for agent processes"
            echo "  reset        - Reset memory environment variables"
            echo "  show         - Show current environment and configuration"
            echo "  create-files - Create environment files for process spawning"
            echo "  apply <file> - Apply environment from specified file"
            echo ""
            echo "Note: Use 'source' to apply environment changes to current shell"
            return 1
            ;;
    esac
}

# Only run main if script is being executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi