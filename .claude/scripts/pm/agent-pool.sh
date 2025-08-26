#!/bin/bash
# Script: agent-pool.sh
# Purpose: Simple agent process pooling for memory efficiency
# Usage: ./agent-pool.sh <action> [epic-name] [additional-params]

set -e
set -u

ACTION="$1"
EPIC_NAME="${2:-}"
POOL_DIR=".claude/agent-pool"
MEMORY_SCRIPT=".claude/scripts/pm/memory-monitor.sh"

# Function to initialize agent pool
function init_pool() {
    mkdir -p "$POOL_DIR"
    
    if [ ! -f "$POOL_DIR/pool-state.json" ]; then
        cat > "$POOL_DIR/pool-state.json" << 'EOF'
{
  "version": "1.0",
  "created": "",
  "pool_size": 0,
  "available_slots": 0,
  "active_agents": [],
  "agent_history": [],
  "memory_efficiency": {
    "reuse_count": 0,
    "memory_saved_gb": 0,
    "avg_agent_lifetime": 0
  }
}
EOF
        
        # Set creation timestamp
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        sed -i.bak "s/\"created\": \"\"/\"created\": \"$timestamp\"/" "$POOL_DIR/pool-state.json"
        rm -f "$POOL_DIR/pool-state.json.bak"
    fi
    
    echo "Agent pool initialized"
}

# Function to check pool status
function check_pool_status() {
    if [ ! -f "$POOL_DIR/pool-state.json" ]; then
        echo "pool_initialized:false"
        return
    fi
    
    # Count active agents (simplified - would use proper JSON parsing in production)
    local active_count=0
    if [ -f "$POOL_DIR/active-agents.txt" ]; then
        active_count=$(wc -l < "$POOL_DIR/active-agents.txt" 2>/dev/null || echo "0")
    fi
    
    # Get memory assessment
    local memory_info=""
    if [ -x "$MEMORY_SCRIPT" ]; then
        memory_info=$($MEMORY_SCRIPT check)
        local spawn_capacity
        spawn_capacity=$(echo "$memory_info" | grep "spawn_capacity:" | cut -d':' -f2)
    else
        spawn_capacity="8"
    fi
    
    echo "pool_initialized:true"
    echo "active_agents:$active_count"
    echo "spawn_capacity:$spawn_capacity"
    echo "pool_efficiency:$(calculate_efficiency)"
}

# Function to calculate pool efficiency
function calculate_efficiency() {
    if [ ! -f "$POOL_DIR/agent-stats.txt" ]; then
        echo "0"
        return
    fi
    
    # Simple efficiency calculation based on agent reuse
    local total_spawns=$(grep -c "SPAWN:" "$POOL_DIR/agent-stats.txt" 2>/dev/null || echo "1")
    local total_reuses=$(grep -c "REUSE:" "$POOL_DIR/agent-stats.txt" 2>/dev/null || echo "0")
    
    local efficiency=0
    if [ "$total_spawns" -gt 0 ]; then
        efficiency=$((total_reuses * 100 / total_spawns))
    fi
    
    echo "$efficiency"
}

# Function to request agent from pool
function request_agent() {
    local epic_name="$1"
    local stream_id="$2"
    local requirements="${3:-general}"
    
    # For now, implement simple coordination rather than actual pooling
    # In a real implementation, this would manage persistent agent processes
    
    local agent_id="agent-$(date +%s)-${stream_id}"
    
    # Log agent request
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") SPAWN: $agent_id for $epic_name/$stream_id ($requirements)" >> "$POOL_DIR/agent-stats.txt"
    echo "$agent_id:$epic_name:$stream_id:$(date +%s)" >> "$POOL_DIR/active-agents.txt"
    
    # Apply memory-optimized environment
    local env_file=".claude/env/agent.env"
    if [ -f "$env_file" ]; then
        echo "agent_id:$agent_id"
        echo "environment_applied:yes"
        echo "memory_limit:$(grep CLAUDE_PM_MEMORY_LIMIT "$env_file" | cut -d'=' -f2)"
        echo "node_options:$(grep NODE_OPTIONS "$env_file" | cut -d'=' -f2)"
    else
        echo "agent_id:$agent_id"
        echo "environment_applied:no"
        echo "warning:no_environment_file"
    fi
}

# Function to release agent back to pool
function release_agent() {
    local agent_id="$1"
    local status="${2:-completed}"
    local memory_usage="${3:-normal}"
    
    # Remove from active agents
    if [ -f "$POOL_DIR/active-agents.txt" ]; then
        grep -v "^$agent_id:" "$POOL_DIR/active-agents.txt" > "$POOL_DIR/active-agents.txt.tmp" 2>/dev/null || true
        mv "$POOL_DIR/active-agents.txt.tmp" "$POOL_DIR/active-agents.txt" 2>/dev/null || true
    fi
    
    # Log agent release
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") RELEASE: $agent_id ($status, memory: $memory_usage)" >> "$POOL_DIR/agent-stats.txt"
    
    # Track memory usage patterns for future optimization
    echo "$agent_id:$status:$memory_usage:$(date +%s)" >> "$POOL_DIR/memory-patterns.txt"
    
    echo "agent_released:$agent_id"
    echo "status:$status"
    echo "memory_usage:$memory_usage"
}

# Function to optimize pool based on usage patterns
function optimize_pool() {
    if [ ! -f "$POOL_DIR/memory-patterns.txt" ]; then
        echo "No usage patterns available for optimization"
        return
    fi
    
    echo "Pool Optimization Analysis"
    echo "========================="
    
    # Analyze memory usage patterns
    local total_agents=$(wc -l < "$POOL_DIR/memory-patterns.txt")
    local high_memory_count=$(grep -c ":high:" "$POOL_DIR/memory-patterns.txt" 2>/dev/null || echo "0")
    local critical_memory_count=$(grep -c ":critical:" "$POOL_DIR/memory-patterns.txt" 2>/dev/null || echo "0")
    
    echo "Total agents processed: $total_agents"
    echo "High memory usage: $high_memory_count"
    echo "Critical memory usage: $critical_memory_count"
    
    # Calculate memory pressure percentage
    local memory_pressure=0
    if [ "$total_agents" -gt 0 ]; then
        memory_pressure=$(((high_memory_count + critical_memory_count) * 100 / total_agents))
    fi
    
    echo "Memory pressure: $memory_pressure%"
    
    # Provide optimization recommendations
    if [ "$memory_pressure" -gt 30 ]; then
        echo ""
        echo "⚠️  HIGH MEMORY PRESSURE DETECTED"
        echo "Recommendations:"
        echo "- Reduce batch size from 8 to 6 agents"
        echo "- Decrease memory per agent from 8GB to 6GB"
        echo "- Increase cleanup frequency"
        echo "- Consider sequential execution for memory-intensive workloads"
    elif [ "$memory_pressure" -gt 15 ]; then
        echo ""
        echo "🔧 MODERATE MEMORY PRESSURE"
        echo "Recommendations:"
        echo "- Monitor memory usage more closely"
        echo "- Consider reducing batch size for large workloads"
        echo "- Implement more aggressive garbage collection"
    else
        echo ""
        echo "✅ OPTIMAL MEMORY USAGE"
        echo "Current configuration is working well"
        echo "Consider increasing batch size if system resources allow"
    fi
}

# Function to get pool statistics
function get_pool_stats() {
    echo "Agent Pool Statistics"
    echo "===================="
    
    if [ ! -d "$POOL_DIR" ]; then
        echo "Agent pool not initialized"
        return
    fi
    
    # Current status
    local active_agents=0
    if [ -f "$POOL_DIR/active-agents.txt" ]; then
        active_agents=$(wc -l < "$POOL_DIR/active-agents.txt" 2>/dev/null || echo "0")
    fi
    
    # Historical stats
    local total_spawns=0
    local total_releases=0
    if [ -f "$POOL_DIR/agent-stats.txt" ]; then
        total_spawns=$(grep -c "SPAWN:" "$POOL_DIR/agent-stats.txt" 2>/dev/null || echo "0")
        total_releases=$(grep -c "RELEASE:" "$POOL_DIR/agent-stats.txt" 2>/dev/null || echo "0")
    fi
    
    echo "Active Agents: $active_agents"
    echo "Total Spawned: $total_spawns"
    echo "Total Released: $total_releases"
    echo "Pool Efficiency: $(calculate_efficiency)%"
    
    # Memory patterns
    if [ -f "$POOL_DIR/memory-patterns.txt" ]; then
        local normal_count=$(grep -c ":normal:" "$POOL_DIR/memory-patterns.txt" 2>/dev/null || echo "0")
        local high_count=$(grep -c ":high:" "$POOL_DIR/memory-patterns.txt" 2>/dev/null || echo "0")
        local critical_count=$(grep -c ":critical:" "$POOL_DIR/memory-patterns.txt" 2>/dev/null || echo "0")
        
        echo ""
        echo "Memory Usage Distribution:"
        echo "- Normal: $normal_count"
        echo "- High: $high_count"
        echo "- Critical: $critical_count"
    fi
}

# Function to cleanup pool resources
function cleanup_pool() {
    echo "Cleaning up agent pool resources..."
    
    # Kill any orphaned processes (placeholder - would implement proper cleanup)
    if command -v pgrep >/dev/null 2>&1; then
        local orphaned=$(pgrep -f "claude.*agent.*pool" | wc -l || echo "0")
        if [ "$orphaned" -gt 0 ]; then
            echo "Warning: Found $orphaned potentially orphaned agent processes"
            # pkill -f "claude.*agent.*pool" 2>/dev/null || true
        fi
    fi
    
    # Clean up old log files (keep last 100 entries)
    for log_file in "$POOL_DIR"/*.txt; do
        [ -f "$log_file" ] || continue
        
        if [ $(wc -l < "$log_file") -gt 100 ]; then
            tail -100 "$log_file" > "$log_file.tmp"
            mv "$log_file.tmp" "$log_file"
        fi
    done
    
    echo "Pool cleanup completed"
}

# Main execution
function main() {
    case "$ACTION" in
        "init")
            init_pool
            ;;
        "status")
            check_pool_status
            ;;
        "request")
            if [ -z "$EPIC_NAME" ] || [ -z "$3" ]; then
                echo "Usage: $0 request <epic-name> <stream-id> [requirements]"
                exit 1
            fi
            request_agent "$EPIC_NAME" "$3" "$4"
            ;;
        "release")
            if [ -z "$3" ]; then
                echo "Usage: $0 release <epic-name> <agent-id> [status] [memory-usage]"
                exit 1
            fi
            release_agent "$3" "$4" "$5"
            ;;
        "optimize")
            optimize_pool
            ;;
        "stats")
            get_pool_stats
            ;;
        "cleanup")
            cleanup_pool
            ;;
        *)
            echo "Usage: $0 <action> [epic-name] [additional-params]"
            echo ""
            echo "Actions:"
            echo "  init      - Initialize agent pool"
            echo "  status    - Check pool status"
            echo "  request   - Request agent from pool"
            echo "  release   - Release agent back to pool"
            echo "  optimize  - Analyze and optimize pool"
            echo "  stats     - Show pool statistics"
            echo "  cleanup   - Cleanup pool resources"
            exit 1
            ;;
    esac
}

main "$@"