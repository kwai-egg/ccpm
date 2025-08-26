#!/bin/bash
# Script: memory-monitor.sh
# Purpose: Monitor system memory and provide memory assessments for agent spawning
# Usage: ./memory-monitor.sh [check|usage|limits|cleanup]

set -e
set -u

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

# Function to get memory information in GB
function get_memory_info() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local total_bytes=$(sysctl -n hw.memsize)
        local total_gb=$((total_bytes / 1024 / 1024 / 1024))
        
        # Get available memory from vm_stat
        local vm_stat=$(vm_stat)
        local free_pages=$(echo "$vm_stat" | grep "Pages free:" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(echo "$vm_stat" | grep "Pages inactive:" | awk '{print $3}' | sed 's/\.//')
        local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
        
        local available_bytes=$(((free_pages + inactive_pages) * page_size))
        local available_gb=$((available_bytes / 1024 / 1024 / 1024))
        
        echo "$total_gb $available_gb"
    else
        # Linux
        local mem_info=$(cat /proc/meminfo)
        local total_kb=$(echo "$mem_info" | grep "MemTotal:" | awk '{print $2}')
        local available_kb=$(echo "$mem_info" | grep "MemAvailable:" | awk '{print $2}')
        
        local total_gb=$((total_kb / 1024 / 1024))
        local available_gb=$((available_kb / 1024 / 1024))
        
        echo "$total_gb $available_gb"
    fi
}

# Function to check if we can spawn more agents
function check_spawn_capacity() {
    local memory_info
    memory_info=$(get_memory_info)
    local total_memory=$(echo "$memory_info" | cut -d' ' -f1)
    local available_memory=$(echo "$memory_info" | cut -d' ' -f2)
    
    # Get configuration
    local max_concurrent=$(get_config_value "max_concurrent_agents" "8")
    local memory_per_agent=$(get_config_value "memory_per_agent_gb" "8")
    local coordinator_memory=$(get_config_value "coordinator_memory_gb" "16")
    local memory_enabled=$(get_config_value "enabled" "true")
    
    # Count currently running agents (placeholder for now)
    local running_agents=0
    if command -v pgrep >/dev/null 2>&1; then
        running_agents=$(pgrep -f "claude.*parallel-worker" | wc -l || echo "0")
    fi
    
    # Calculate available slots
    local available_slots=$((max_concurrent - running_agents))
    
    # Calculate memory-based capacity
    local reserved_memory=$((coordinator_memory + (running_agents * memory_per_agent)))
    local remaining_memory=$((available_memory - reserved_memory))
    local memory_based_slots=$((remaining_memory / memory_per_agent))
    
    # Use the minimum of the two constraints
    local spawn_capacity=$available_slots
    if [ "$memory_based_slots" -lt "$available_slots" ]; then
        spawn_capacity=$memory_based_slots
    fi
    
    # Ensure non-negative
    if [ "$spawn_capacity" -lt 0 ]; then
        spawn_capacity=0
    fi
    
    echo "total_memory:$total_memory"
    echo "available_memory:$available_memory"
    echo "running_agents:$running_agents"
    echo "max_concurrent:$max_concurrent"
    echo "spawn_capacity:$spawn_capacity"
    echo "memory_enabled:$memory_enabled"
}

# Function to get current memory usage
function get_memory_usage() {
    local memory_info
    memory_info=$(get_memory_info)
    local total_memory=$(echo "$memory_info" | cut -d' ' -f1)
    local available_memory=$(echo "$memory_info" | cut -d' ' -f2)
    local used_memory=$((total_memory - available_memory))
    local usage_percent=$((used_memory * 100 / total_memory))
    
    echo "Memory Usage Report"
    echo "=================="
    echo "Total Memory: ${total_memory}GB"
    echo "Used Memory: ${used_memory}GB"
    echo "Available Memory: ${available_memory}GB"
    echo "Usage: ${usage_percent}%"
}

# Function to show memory limits from configuration
function show_memory_limits() {
    echo "Memory Configuration"
    echo "==================="
    echo "Memory Management Enabled: $(get_config_value "enabled" "true")"
    echo "Max Concurrent Agents: $(get_config_value "max_concurrent_agents" "8")"
    echo "Memory per Agent: $(get_config_value "memory_per_agent_gb" "8")GB"
    echo "Total Memory Limit: $(get_config_value "total_memory_limit_gb" "96")GB"
    echo "Coordinator Memory: $(get_config_value "coordinator_memory_gb" "16")GB"
    echo "Monitoring Enabled: $(get_config_value "monitoring_enabled" "true")"
    echo "Cleanup Timeout: $(get_config_value "cleanup_timeout" "30")s"
    echo "Retry on Memory Limit: $(get_config_value "retry_on_memory_limit" "true")"
}

# Function to cleanup memory (force garbage collection if possible)
function cleanup_memory() {
    echo "Performing memory cleanup..."
    
    # Trigger garbage collection for any Node.js processes if possible
    if command -v killall >/dev/null 2>&1; then
        # Send USR2 signal to trigger GC in Node.js processes (if configured)
        pkill -USR2 -f "node.*claude" 2>/dev/null || true
    fi
    
    # System-level memory cleanup
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - purge inactive memory
        sudo purge 2>/dev/null || echo "Note: 'sudo purge' failed or not available"
    else
        # Linux - drop caches
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || echo "Note: Cache dropping failed or requires sudo"
    fi
    
    echo "Memory cleanup completed"
}

# Function for continuous monitoring mode
function continuous_monitoring() {
    local interval="${2:-5}"  # Default 5 second interval
    
    echo "Starting continuous memory monitoring (interval: ${interval}s)"
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Cleanup function for continuous mode
    cleanup_continuous() {
        echo ""
        echo "Stopping continuous monitoring..."
        exit 0
    }
    
    # Set trap for cleanup
    trap cleanup_continuous INT TERM
    
    while true; do
        echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
        
        # Show memory usage
        get_memory_usage
        echo ""
        
        # Show spawn capacity
        echo "Spawn Capacity:"
        check_spawn_capacity | grep -E "(spawn_capacity|running_agents|memory_enabled)" | sed 's/^/  /'
        echo ""
        
        sleep "$interval"
    done
}

# Function for daemon monitoring mode (for background processes)
function daemon_monitoring() {
    local interval="${2:-10}"  # Default 10 second interval for daemon
    local log_file="${3:-/tmp/memory-monitor-daemon.log}"
    
    # Run in background, logging to file
    while true; do
        {
            echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
            get_memory_usage
            echo ""
            check_spawn_capacity | grep -E "(spawn_capacity|running_agents|available_memory)" | sed 's/^/  /'
            echo ""
        } >> "$log_file"
        
        sleep "$interval"
    done &
    
    echo "daemon_pid:$!"
    echo "log_file:$log_file"
    echo "interval:${interval}s"
}

# Main execution
function main() {
    local command="${1:-check}"
    
    case "$command" in
        "check")
            check_spawn_capacity
            ;;
        "usage")
            get_memory_usage
            ;;
        "limits")
            show_memory_limits
            ;;
        "cleanup")
            cleanup_memory
            ;;
        "continuous")
            continuous_monitoring "$@"
            ;;
        "daemon")
            daemon_monitoring "$@"
            ;;
        *)
            echo "Usage: $0 [check|usage|limits|cleanup|continuous|daemon]"
            echo ""
            echo "Commands:"
            echo "  check      - Check current spawn capacity based on memory"
            echo "  usage      - Show current memory usage"
            echo "  limits     - Show configured memory limits"
            echo "  cleanup    - Perform memory cleanup operations"
            echo "  continuous - Continuous monitoring (interactive)"
            echo "  daemon     - Background daemon monitoring"
            exit 1
            ;;
    esac
}

# Call main function
main "$@"