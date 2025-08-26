#!/bin/bash
# Script: coordination-memory.sh
# Purpose: Memory-aware coordination for parallel agent execution
# Usage: ./coordination-memory.sh <epic-name> <action> [stream-count]

set -e
set -u

EPIC_NAME="$1"
ACTION="$2"
STREAM_COUNT="${3:-0}"

COORDINATION_DIR=".claude/epics/$EPIC_NAME/coordination"
MEMORY_SCRIPT=".claude/scripts/pm/memory-monitor.sh"

# Function to log coordination events
function log_event() {
    local message="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] $message" >> "$COORDINATION_DIR/memory-log.md"
}

# Function to assess memory before spawning
function assess_memory_capacity() {
    local requested_streams="$1"
    
    if [ ! -x "$MEMORY_SCRIPT" ]; then
        echo "memory_assessment:disabled"
        echo "spawn_capacity:$requested_streams"
        echo "reason:memory_monitor_unavailable"
        return 0
    fi
    
    local capacity_info
    capacity_info=$($MEMORY_SCRIPT check)
    
    local spawn_capacity
    spawn_capacity=$(echo "$capacity_info" | grep "spawn_capacity:" | cut -d':' -f2)
    
    local available_memory
    available_memory=$(echo "$capacity_info" | grep "available_memory:" | cut -d':' -f2)
    
    local running_agents
    running_agents=$(echo "$capacity_info" | grep "running_agents:" | cut -d':' -f2)
    
    local memory_enabled
    memory_enabled=$(echo "$capacity_info" | grep "memory_enabled:" | cut -d':' -f2)
    
    echo "memory_assessment:enabled"
    echo "available_memory:$available_memory"
    echo "running_agents:$running_agents"
    echo "spawn_capacity:$spawn_capacity"
    echo "requested_streams:$requested_streams"
    echo "memory_enabled:$memory_enabled"
    
    if [ "$spawn_capacity" -ge "$requested_streams" ]; then
        echo "assessment:approved"
        log_event "Memory assessment approved: $requested_streams streams (capacity: $spawn_capacity)"
    else
        echo "assessment:limited"
        echo "recommended_batch_size:$spawn_capacity"
        log_event "Memory assessment limited: requested $requested_streams, capacity $spawn_capacity"
    fi
}

# Function to track agent spawn
function track_agent_spawn() {
    local stream_id="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "stream_id:$stream_id" >> "$COORDINATION_DIR/active-agents.log"
    echo "spawn_time:$timestamp" >> "$COORDINATION_DIR/active-agents.log"
    echo "status:spawned" >> "$COORDINATION_DIR/active-agents.log"
    echo "---" >> "$COORDINATION_DIR/active-agents.log"
    
    log_event "Agent spawned for stream: $stream_id"
}

# Function to track agent completion
function track_agent_completion() {
    local stream_id="$1"
    local status="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Mark completion in active agents log
    sed -i.bak "/stream_id:$stream_id/,/---/{
        s/status:spawned/status:completed/
        /^---$/i\\
completion_time:$timestamp\\
final_status:$status
    }" "$COORDINATION_DIR/active-agents.log" 2>/dev/null || true
    
    log_event "Agent completed for stream: $stream_id (status: $status)"
}

# Function to cleanup completed agents from tracking
function cleanup_completed_agents() {
    local temp_file=$(mktemp)
    
    # Keep only active agents
    awk '
        /^stream_id:/ { 
            stream_block = $0 "\n"
            in_block = 1
            next
        }
        in_block && /^---$/ {
            if (stream_block !~ /status:completed/) {
                print stream_block $0
            }
            stream_block = ""
            in_block = 0
            next
        }
        in_block {
            stream_block = stream_block $0 "\n"
            next
        }
    ' "$COORDINATION_DIR/active-agents.log" > "$temp_file" 2>/dev/null || true
    
    mv "$temp_file" "$COORDINATION_DIR/active-agents.log" 2>/dev/null || true
    
    log_event "Cleaned up completed agents from tracking"
}

# Function to get current memory usage for monitoring
function monitor_memory_usage() {
    if [ ! -x "$MEMORY_SCRIPT" ]; then
        echo "monitoring:disabled"
        return 0
    fi
    
    local usage_info
    usage_info=$($MEMORY_SCRIPT usage)
    
    # Extract key metrics
    local total_memory=$(echo "$usage_info" | grep "Total Memory:" | cut -d':' -f2 | xargs)
    local used_memory=$(echo "$usage_info" | grep "Used Memory:" | cut -d':' -f2 | xargs)
    local available_memory=$(echo "$usage_info" | grep "Available Memory:" | cut -d':' -f2 | xargs)
    local usage_percent=$(echo "$usage_info" | grep "Usage:" | cut -d':' -f2 | xargs)
    
    echo "monitoring:enabled"
    echo "total_memory:$total_memory"
    echo "used_memory:$used_memory"
    echo "available_memory:$available_memory"
    echo "usage_percent:$usage_percent"
    
    # Log high memory usage
    local usage_num=$(echo "$usage_percent" | sed 's/%//')
    if [ "$usage_num" -gt 85 ]; then
        log_event "HIGH MEMORY USAGE WARNING: $usage_percent"
    fi
}

# Function to force memory cleanup
function force_cleanup() {
    log_event "Forcing memory cleanup"
    
    if [ -x "$MEMORY_SCRIPT" ]; then
        $MEMORY_SCRIPT cleanup
    fi
    
    cleanup_completed_agents
    
    log_event "Memory cleanup completed"
}

# Function to calculate dynamic batch size
function calculate_batch_size() {
    local total_streams="$1"
    local capacity_info
    capacity_info=$(assess_memory_capacity "$total_streams")
    
    local spawn_capacity
    spawn_capacity=$(echo "$capacity_info" | grep "spawn_capacity:" | cut -d':' -f2)
    
    local assessment
    assessment=$(echo "$capacity_info" | grep "assessment:" | cut -d':' -f2)
    
    if [ "$assessment" = "approved" ]; then
        echo "batch_size:$total_streams"
        echo "batches:1"
        echo "strategy:single_batch"
    else
        local batches=1
        if [ "$spawn_capacity" -gt 0 ]; then
            batches=$(((total_streams + spawn_capacity - 1) / spawn_capacity))
        fi
        
        echo "batch_size:$spawn_capacity"
        echo "batches:$batches"
        echo "strategy:multi_batch"
        echo "total_streams:$total_streams"
    fi
    
    log_event "Calculated batching: $total_streams streams -> $batches batches of $spawn_capacity"
}

# Main execution
function main() {
    # Ensure coordination directory exists
    mkdir -p "$COORDINATION_DIR"
    
    # Initialize memory log if it doesn't exist
    if [ ! -f "$COORDINATION_DIR/memory-log.md" ]; then
        echo "# Memory Management Log for Epic: $EPIC_NAME" > "$COORDINATION_DIR/memory-log.md"
        echo "Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$COORDINATION_DIR/memory-log.md"
        echo "" >> "$COORDINATION_DIR/memory-log.md"
    fi
    
    case "$ACTION" in
        "assess")
            assess_memory_capacity "$STREAM_COUNT"
            ;;
        "spawn")
            track_agent_spawn "$STREAM_COUNT"  # STREAM_COUNT is stream_id in this case
            ;;
        "complete")
            track_agent_completion "$STREAM_COUNT" "${4:-success}"
            ;;
        "monitor")
            monitor_memory_usage
            ;;
        "cleanup")
            force_cleanup
            ;;
        "batch")
            calculate_batch_size "$STREAM_COUNT"
            ;;
        *)
            echo "Usage: $0 <epic-name> <action> [stream-count/stream-id]"
            echo ""
            echo "Actions:"
            echo "  assess  - Assess memory capacity for spawning streams"
            echo "  spawn   - Track agent spawn (stream-id required)"
            echo "  complete- Track agent completion (stream-id required)"
            echo "  monitor - Monitor current memory usage"
            echo "  cleanup - Force memory cleanup"
            echo "  batch   - Calculate dynamic batch size"
            exit 1
            ;;
    esac
}

main "$@"