#!/bin/bash
# Script: memory-retry.sh
# Purpose: Handle memory-based retry logic for failed streams
# Usage: ./memory-retry.sh <epic-name> <action> [stream-id]

set -e
set -u

EPIC_NAME="$1"
ACTION="$2"
STREAM_ID="${3:-}"

COORDINATION_DIR=".claude/epics/$EPIC_NAME/coordination"
MEMORY_SCRIPT=".claude/scripts/pm/memory-monitor.sh"
MEMORY_COORD_SCRIPT=".claude/scripts/pm/coordination-memory.sh"

# Function to log retry events
function log_retry_event() {
    local message="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] RETRY: $message" >> "$COORDINATION_DIR/memory-log.md"
}

# Function to check if failure was memory-related
function is_memory_failure() {
    local stream_id="$1"
    local failure_file="$COORDINATION_DIR/stream-${stream_id}-blocked.md"
    
    if [ ! -f "$failure_file" ]; then
        return 1
    fi
    
    # Check for memory-related error patterns
    if grep -i -E "(heap|memory|out of memory|allocation|oom|ENOMEM)" "$failure_file" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Function to assess retry feasibility
function assess_retry_feasibility() {
    local stream_id="$1"
    
    # Check memory capacity
    local capacity_info
    capacity_info=$($MEMORY_COORD_SCRIPT "$EPIC_NAME" assess 1)
    
    local spawn_capacity
    spawn_capacity=$(echo "$capacity_info" | grep "spawn_capacity:" | cut -d':' -f2)
    
    local available_memory
    available_memory=$(echo "$capacity_info" | grep "available_memory:" | cut -d':' -f2)
    
    echo "feasibility_check:completed"
    echo "stream_id:$stream_id"
    echo "spawn_capacity:$spawn_capacity"
    echo "available_memory:${available_memory}GB"
    
    if [ "$spawn_capacity" -gt 0 ] && [ "$available_memory" -gt 4 ]; then
        echo "retry_feasible:yes"
        log_retry_event "Retry feasible for stream $stream_id (capacity: $spawn_capacity, memory: ${available_memory}GB)"
    else
        echo "retry_feasible:no"
        echo "reason:insufficient_memory"
        log_retry_event "Retry not feasible for stream $stream_id (capacity: $spawn_capacity, memory: ${available_memory}GB)"
    fi
}

# Function to prepare memory-optimized retry
function prepare_memory_retry() {
    local stream_id="$1"
    local retry_attempt="${4:-1}"
    
    # Force memory cleanup before retry
    if [ -x "$MEMORY_SCRIPT" ]; then
        $MEMORY_SCRIPT cleanup
        sleep 2  # Allow cleanup to take effect
    fi
    
    # Create retry configuration with reduced memory requirements
    local retry_config="$COORDINATION_DIR/stream-${stream_id}-retry-config.md"
    
    cat > "$retry_config" << EOF
# Memory-Optimized Retry Configuration
Stream ID: $stream_id
Retry Attempt: $retry_attempt
Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Memory Optimizations for Retry
- Reduced heap size: 4096MB (50% of normal)
- Aggressive garbage collection enabled
- Memory monitoring: every 30 seconds
- Timeout: 1800 seconds (30 minutes)
- Early termination on memory pressure

## Retry Strategy
- Process files in smaller batches
- Commit more frequently to clear memory
- Avoid loading large files entirely into memory
- Use streaming operations where possible

## Monitoring
- Memory usage will be logged every 30 seconds
- Agent will self-terminate if memory usage exceeds 90%
- Coordination system will track memory patterns

EOF
    
    echo "retry_config_created:$retry_config"
    log_retry_event "Created memory-optimized retry config for stream $stream_id (attempt $retry_attempt)"
}

# Function to execute memory-optimized retry
function execute_memory_retry() {
    local stream_id="$1"
    local retry_attempt="${4:-1}"
    
    # Prepare retry environment
    prepare_memory_retry "$stream_id" "$retry_attempt"
    
    # Get original stream requirements
    local stream_file="$COORDINATION_DIR/stream-${stream_id}-requirements.md"
    if [ ! -f "$stream_file" ]; then
        echo "error:missing_stream_requirements"
        return 1
    fi
    
    # Create memory-optimized retry prompt
    local retry_prompt="$COORDINATION_DIR/stream-${stream_id}-retry-prompt.md"
    
    cat > "$retry_prompt" << EOF
# MEMORY-OPTIMIZED RETRY for Stream $stream_id

## Previous Failure Analysis
This stream previously failed due to memory constraints. This retry uses:
- Reduced memory allocation (4GB instead of 8GB)
- Aggressive garbage collection
- Streaming file processing
- Frequent commits to clear memory

## Memory Management Instructions
1. Set NODE_OPTIONS="--max-old-space-size=4096 --expose-gc --optimize_for_size"
2. Call gc() manually after processing large operations
3. Process files one at a time, not in batches
4. Commit after every significant change
5. Monitor memory usage - if it exceeds 90%, stop and report
6. Use stream-based file operations instead of loading entire files

## Memory Monitoring
- Report memory status every 10 operations
- Include memory usage in all status updates
- Terminate gracefully if memory pressure detected

## Original Requirements
$(cat "$stream_file")

## Success Criteria for Retry
- Complete the work within memory constraints
- Report "memory_retry:successful" on completion
- Provide memory usage statistics in final report

EOF
    
    echo "retry_prompt_created:$retry_prompt"
    log_retry_event "Created memory-optimized retry prompt for stream $stream_id"
    
    # Track the retry attempt
    $MEMORY_COORD_SCRIPT "$EPIC_NAME" spawn "retry-${stream_id}-${retry_attempt}"
}

# Function to verify cleanup after agent completion
function verify_cleanup() {
    local stream_id="$1"
    local cleanup_timeout=30
    
    log_retry_event "Starting cleanup verification for stream $stream_id"
    
    # Wait for any lingering processes to complete
    sleep 5
    
    # Check for remaining agent processes
    local remaining_processes=0
    if command -v pgrep >/dev/null 2>&1; then
        remaining_processes=$(pgrep -f "claude.*parallel.*$stream_id" | wc -l || echo "0")
    fi
    
    # Force cleanup if processes remain
    if [ "$remaining_processes" -gt 0 ]; then
        log_retry_event "Warning: $remaining_processes processes still running for stream $stream_id"
        
        # Try graceful termination first
        pkill -TERM -f "claude.*parallel.*$stream_id" 2>/dev/null || true
        sleep 10
        
        # Force kill if necessary
        pkill -KILL -f "claude.*parallel.*$stream_id" 2>/dev/null || true
        sleep 5
        
        remaining_processes=$(pgrep -f "claude.*parallel.*$stream_id" | wc -l || echo "0")
    fi
    
    # Check memory cleanup
    local memory_before memory_after
    memory_before=$(cat "$COORDINATION_DIR/memory-before-${stream_id}.txt" 2>/dev/null || echo "unknown")
    
    if [ -x "$MEMORY_SCRIPT" ]; then
        $MEMORY_SCRIPT cleanup
        memory_after=$($MEMORY_SCRIPT usage | grep "Available Memory:" | cut -d':' -f2 | xargs)
    else
        memory_after="unknown"
    fi
    
    # Record cleanup results
    cat > "$COORDINATION_DIR/cleanup-${stream_id}.md" << EOF
# Cleanup Verification for Stream $stream_id
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Process Cleanup
- Remaining processes: $remaining_processes
- Cleanup timeout: ${cleanup_timeout}s
- Cleanup method: $([ "$remaining_processes" -eq 0 ] && echo "graceful" || echo "forced")

## Memory Cleanup
- Memory before: $memory_before
- Memory after: $memory_after
- Cleanup performed: yes

## Cleanup Status
$([ "$remaining_processes" -eq 0 ] && echo "✅ SUCCESSFUL" || echo "⚠️  PARTIAL")

EOF
    
    echo "cleanup_verification:completed"
    echo "remaining_processes:$remaining_processes"
    echo "memory_before:$memory_before"
    echo "memory_after:$memory_after"
    echo "cleanup_status:$([ "$remaining_processes" -eq 0 ] && echo "successful" || echo "partial")"
    
    log_retry_event "Cleanup verification completed for stream $stream_id (processes: $remaining_processes)"
}

# Function to get retry statistics
function get_retry_stats() {
    echo "Memory Retry Statistics for Epic: $EPIC_NAME"
    echo "============================================="
    
    if [ ! -d "$COORDINATION_DIR" ]; then
        echo "No coordination directory found"
        return 0
    fi
    
    local total_retries=0
    local successful_retries=0
    local failed_retries=0
    
    for retry_config in "$COORDINATION_DIR"/stream-*-retry-config.md; do
        [ -f "$retry_config" ] || continue
        total_retries=$((total_retries + 1))
        
        local stream_id=$(basename "$retry_config" | sed 's/stream-//' | sed 's/-retry-config.md//')
        local cleanup_file="$COORDINATION_DIR/cleanup-${stream_id}.md"
        
        if [ -f "$cleanup_file" ] && grep -q "SUCCESSFUL" "$cleanup_file"; then
            successful_retries=$((successful_retries + 1))
        else
            failed_retries=$((failed_retries + 1))
        fi
    done
    
    echo "Total memory-based retries: $total_retries"
    echo "Successful retries: $successful_retries"
    echo "Failed retries: $failed_retries"
    echo "Success rate: $((successful_retries * 100 / (total_retries > 0 ? total_retries : 1)))%"
}

# Main execution
function main() {
    # Ensure coordination directory exists
    mkdir -p "$COORDINATION_DIR"
    
    case "$ACTION" in
        "check")
            if [ -z "$STREAM_ID" ]; then
                echo "Stream ID required for check action"
                exit 1
            fi
            if is_memory_failure "$STREAM_ID"; then
                echo "memory_failure:yes"
                assess_retry_feasibility "$STREAM_ID"
            else
                echo "memory_failure:no"
            fi
            ;;
        "prepare")
            if [ -z "$STREAM_ID" ]; then
                echo "Stream ID required for prepare action"
                exit 1
            fi
            prepare_memory_retry "$STREAM_ID"
            ;;
        "execute")
            if [ -z "$STREAM_ID" ]; then
                echo "Stream ID required for execute action"
                exit 1
            fi
            execute_memory_retry "$STREAM_ID"
            ;;
        "verify-cleanup")
            if [ -z "$STREAM_ID" ]; then
                echo "Stream ID required for verify-cleanup action"
                exit 1
            fi
            verify_cleanup "$STREAM_ID"
            ;;
        "stats")
            get_retry_stats
            ;;
        *)
            echo "Usage: $0 <epic-name> <action> [stream-id]"
            echo ""
            echo "Actions:"
            echo "  check         - Check if stream failure was memory-related"
            echo "  prepare       - Prepare memory-optimized retry configuration"
            echo "  execute       - Execute memory-optimized retry"
            echo "  verify-cleanup- Verify cleanup after agent completion"
            echo "  stats         - Show retry statistics for epic"
            exit 1
            ;;
    esac
}

main "$@"