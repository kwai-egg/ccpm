#!/bin/bash
# Script: coordinator-setup.sh
# Purpose: Configure NODE_OPTIONS and environment for coordinator process
# Usage: ./coordinator-setup.sh [apply|check|reset]

set -e
set -u

ACTION="${1:-apply}"
ENV_SCRIPT=".claude/scripts/pm/memory-env.sh"
COORDINATOR_ENV=".claude/env/coordinator.env"

# Function to apply coordinator environment
function apply_coordinator_env() {
    if [ ! -f "$COORDINATOR_ENV" ]; then
        echo "Creating coordinator environment configuration..."
        if [ -x "$ENV_SCRIPT" ]; then
            $ENV_SCRIPT create-files
        else
            echo "❌ Memory environment script not found: $ENV_SCRIPT"
            exit 1
        fi
    fi
    
    # Apply environment variables
    if [ -f "$COORDINATOR_ENV" ]; then
        echo "Applying coordinator memory configuration..."
        
        # Source the environment file to set variables
        source "$COORDINATOR_ENV"
        
        echo "✅ Coordinator environment applied:"
        echo "  NODE_OPTIONS: $NODE_OPTIONS"
        echo "  CLAUDE_PM_ROLE: $CLAUDE_PM_ROLE"
        echo "  CLAUDE_PM_MEMORY_LIMIT: $CLAUDE_PM_MEMORY_LIMIT MB"
        
        # Export for child processes
        export NODE_OPTIONS
        export CLAUDE_PM_ROLE
        export CLAUDE_PM_MEMORY_LIMIT
        
        # Set additional coordinator-specific variables
        export CLAUDE_PM_COORDINATOR=true
        export CLAUDE_PM_SPAWN_LIMIT=8
        export CLAUDE_PM_MEMORY_MONITORING=true
        
        echo "  CLAUDE_PM_COORDINATOR: $CLAUDE_PM_COORDINATOR"
        echo "  CLAUDE_PM_SPAWN_LIMIT: $CLAUDE_PM_SPAWN_LIMIT"
        echo "  CLAUDE_PM_MEMORY_MONITORING: $CLAUDE_PM_MEMORY_MONITORING"
        
    else
        echo "❌ Coordinator environment file not found: $COORDINATOR_ENV"
        exit 1
    fi
}

# Function to check current coordinator environment
function check_coordinator_env() {
    echo "Current Coordinator Environment"
    echo "=============================="
    
    echo "NODE_OPTIONS: ${NODE_OPTIONS:-<not set>}"
    echo "CLAUDE_PM_ROLE: ${CLAUDE_PM_ROLE:-<not set>}"
    echo "CLAUDE_PM_MEMORY_LIMIT: ${CLAUDE_PM_MEMORY_LIMIT:-<not set>} MB"
    echo "CLAUDE_PM_COORDINATOR: ${CLAUDE_PM_COORDINATOR:-<not set>}"
    echo "CLAUDE_PM_SPAWN_LIMIT: ${CLAUDE_PM_SPAWN_LIMIT:-<not set>}"
    echo "CLAUDE_PM_MEMORY_MONITORING: ${CLAUDE_PM_MEMORY_MONITORING:-<not set>}"
    
    # Check if environment file exists
    echo ""
    echo "Configuration Files:"
    if [ -f "$COORDINATOR_ENV" ]; then
        echo "✅ Coordinator env file: $COORDINATOR_ENV"
        echo "   Contents:"
        cat "$COORDINATOR_ENV" | sed 's/^/     /'
    else
        echo "❌ Coordinator env file not found: $COORDINATOR_ENV"
    fi
    
    # Check memory script
    if [ -x "$ENV_SCRIPT" ]; then
        echo "✅ Memory env script: $ENV_SCRIPT"
    else
        echo "❌ Memory env script not found: $ENV_SCRIPT"
    fi
}

# Function to reset coordinator environment
function reset_coordinator_env() {
    echo "Resetting coordinator environment..."
    
    unset NODE_OPTIONS
    unset CLAUDE_PM_ROLE
    unset CLAUDE_PM_MEMORY_LIMIT
    unset CLAUDE_PM_COORDINATOR
    unset CLAUDE_PM_SPAWN_LIMIT
    unset CLAUDE_PM_MEMORY_MONITORING
    
    echo "✅ Coordinator environment reset"
}

# Function to create startup script for coordinator
function create_startup_script() {
    local startup_script=".claude/scripts/pm/start-coordinator.sh"
    
    cat > "$startup_script" << 'EOF'
#!/bin/bash
# Coordinator startup script with memory optimization
# This script should be sourced, not executed

echo "Starting Claude Code PM Coordinator with memory optimization..."

# Apply coordinator environment
if [ -f ".claude/scripts/pm/coordinator-setup.sh" ]; then
    source .claude/scripts/pm/coordinator-setup.sh apply
else
    echo "❌ Coordinator setup script not found"
    exit 1
fi

# Initialize memory monitoring
if [ -f ".claude/scripts/pm/memory-monitor.sh" ]; then
    echo "Current system memory status:"
    .claude/scripts/pm/memory-monitor.sh usage
    echo ""
fi

# Initialize agent pool
if [ -f ".claude/scripts/pm/agent-pool.sh" ]; then
    .claude/scripts/pm/agent-pool.sh init
fi

# Initialize memory feedback system
if [ -f ".claude/scripts/pm/memory-feedback.sh" ]; then
    .claude/scripts/pm/memory-feedback.sh init
fi

echo "✅ Claude Code PM Coordinator ready with memory optimization"
echo "   Use '/pm:epic-start <epic-name>' to begin parallel execution"
EOF
    
    chmod +x "$startup_script"
    echo "✅ Created coordinator startup script: $startup_script"
}

# Function to validate coordinator configuration
function validate_configuration() {
    echo "Validating Coordinator Configuration"
    echo "=================================="
    
    local errors=0
    
    # Check environment file
    if [ ! -f "$COORDINATOR_ENV" ]; then
        echo "❌ Missing coordinator environment file"
        errors=$((errors + 1))
    else
        echo "✅ Coordinator environment file exists"
        
        # Validate environment file contents
        if ! grep -q "NODE_OPTIONS=" "$COORDINATOR_ENV"; then
            echo "❌ NODE_OPTIONS not found in environment file"
            errors=$((errors + 1))
        fi
        
        if ! grep -q "CLAUDE_PM_ROLE=coordinator" "$COORDINATOR_ENV"; then
            echo "❌ CLAUDE_PM_ROLE not set to coordinator"
            errors=$((errors + 1))
        fi
    fi
    
    # Check memory script
    if [ ! -x "$ENV_SCRIPT" ]; then
        echo "❌ Memory environment script not executable"
        errors=$((errors + 1))
    else
        echo "✅ Memory environment script available"
    fi
    
    # Check configuration file
    if [ ! -f "~/.claude/.claude-pm.yaml" ]; then
        echo "❌ Configuration file not found"
        errors=$((errors + 1))
    else
        echo "✅ Configuration file exists"
        
        # Validate memory configuration
        if ! grep -q "memory_management:" "~/.claude/.claude-pm.yaml"; then
            echo "❌ Memory management not configured"
            errors=$((errors + 1))
        fi
    fi
    
    echo ""
    if [ "$errors" -eq 0 ]; then
        echo "✅ All coordinator configuration checks passed"
    else
        echo "❌ Found $errors configuration issues"
        echo "   Run './coordinator-setup.sh apply' to fix"
    fi
    
    return $errors
}

# Main execution
function main() {
    case "$ACTION" in
        "apply")
            apply_coordinator_env
            ;;
        "check")
            check_coordinator_env
            ;;
        "reset")
            reset_coordinator_env
            ;;
        "create-startup")
            create_startup_script
            ;;
        "validate")
            validate_configuration
            ;;
        *)
            echo "Usage: $0 [apply|check|reset|create-startup|validate]"
            echo ""
            echo "Actions:"
            echo "  apply         - Apply coordinator memory configuration"
            echo "  check         - Check current coordinator environment"
            echo "  reset         - Reset coordinator environment variables"
            echo "  create-startup- Create coordinator startup script"
            echo "  validate      - Validate coordinator configuration"
            echo ""
            echo "Note: Use 'source $0 apply' to apply environment to current shell"
            exit 1
            ;;
    esac
}

main "$@"