#!/bin/bash
# Script: memory-feedback.sh
# Purpose: Implement feedback loop for future spawning decisions based on memory patterns
# Usage: ./memory-feedback.sh <action> [epic-name] [additional-params]

set -e
set -u

ACTION="$1"
EPIC_NAME="${2:-}"
FEEDBACK_DIR=".claude/memory-feedback"
CONFIG_FILE="~/.claude/.claude-pm.yaml"

# Function to initialize feedback system
function init_feedback_system() {
    mkdir -p "$FEEDBACK_DIR"
    
    if [ ! -f "$FEEDBACK_DIR/patterns.json" ]; then
        cat > "$FEEDBACK_DIR/patterns.json" << 'EOF'
{
  "version": "1.0",
  "created": "",
  "last_updated": "",
  "patterns": {
    "successful_configurations": [],
    "failed_configurations": [],
    "optimal_batch_sizes": {},
    "memory_usage_patterns": {},
    "performance_metrics": {}
  },
  "recommendations": {
    "default_batch_size": 8,
    "memory_per_agent": 8,
    "max_concurrent": 8,
    "confidence_score": 0.0
  }
}
EOF
        
        # Set timestamps
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        sed -i.bak "s/\"created\": \"\"/\"created\": \"$timestamp\"/" "$FEEDBACK_DIR/patterns.json"
        sed -i.bak "s/\"last_updated\": \"\"/\"last_updated\": \"$timestamp\"/" "$FEEDBACK_DIR/patterns.json"
        rm -f "$FEEDBACK_DIR/patterns.json.bak"
    fi
    
    echo "Feedback system initialized"
}

# Function to record execution pattern
function record_execution_pattern() {
    local epic_name="$1"
    local batch_size="$2"
    local total_streams="$3"
    local success_rate="$4"
    local peak_memory="$5"
    local execution_time="$6"
    
    local coordination_dir=".claude/epics/$epic_name/coordination"
    
    if [ ! -d "$coordination_dir" ]; then
        echo "❌ Coordination directory not found for epic: $epic_name"
        return 1
    fi
    
    # Create execution record
    local record_file="$FEEDBACK_DIR/execution-$(date +%s)-${epic_name}.json"
    
    cat > "$record_file" << EOF
{
  "epic_name": "$epic_name",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "configuration": {
    "batch_size": $batch_size,
    "total_streams": $total_streams,
    "memory_per_agent": $(get_config_value "memory_per_agent_gb" 8),
    "max_concurrent": $(get_config_value "max_concurrent_agents" 8)
  },
  "results": {
    "success_rate": $success_rate,
    "peak_memory_usage": $peak_memory,
    "execution_time_seconds": $execution_time,
    "memory_failures": $(count_memory_failures "$epic_name"),
    "retries_needed": $(count_retries "$epic_name")
  },
  "classification": "$(classify_execution "$success_rate" "$peak_memory")"
}
EOF
    
    echo "Execution pattern recorded: $record_file"
    
    # Update patterns database
    update_patterns_database "$record_file"
}

# Function to get configuration value from YAML
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

# Function to count memory failures for an epic
function count_memory_failures() {
    local epic_name="$1"
    local coordination_dir=".claude/epics/$epic_name/coordination"
    
    if [ ! -d "$coordination_dir" ]; then
        echo "0"
        return
    fi
    
    find "$coordination_dir" -name "*retry-config.md" 2>/dev/null | wc -l | xargs
}

# Function to count retries for an epic
function count_retries() {
    local epic_name="$1"
    local coordination_dir=".claude/epics/$epic_name/coordination"
    
    if [ ! -d "$coordination_dir" ] || [ ! -f "$coordination_dir/memory-log.md" ]; then
        echo "0"
        return
    fi
    
    grep -c "RETRY:" "$coordination_dir/memory-log.md" 2>/dev/null || echo "0"
}

# Function to classify execution quality
function classify_execution() {
    local success_rate="$1"
    local peak_memory="$2"
    
    # Remove % sign and convert to number
    local success_num=$(echo "$success_rate" | sed 's/%//')
    local memory_num=$(echo "$peak_memory" | sed 's/%//')
    
    if [ "$success_num" -ge 95 ] && [ "$memory_num" -le 80 ]; then
        echo "excellent"
    elif [ "$success_num" -ge 90 ] && [ "$memory_num" -le 85 ]; then
        echo "good"
    elif [ "$success_num" -ge 80 ]; then
        echo "acceptable"
    else
        echo "poor"
    fi
}

# Function to update patterns database (simplified - would use proper JSON in production)
function update_patterns_database() {
    local record_file="$1"
    
    # For now, just log the update (in production, would parse JSON and update patterns)
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): Updated patterns database with $record_file" >> "$FEEDBACK_DIR/update-log.txt"
}

# Function to generate recommendations based on historical patterns
function generate_recommendations() {
    echo "Memory Management Recommendations"
    echo "================================"
    
    if [ ! -d "$FEEDBACK_DIR" ] || [ -z "$(ls -A "$FEEDBACK_DIR"/execution-*.json 2>/dev/null)" ]; then
        echo "Insufficient data for recommendations. Using default values:"
        echo "- Default batch size: 8 agents"
        echo "- Memory per agent: 8GB"
        echo "- Max concurrent: 8 agents"
        echo "- Confidence: Low (no historical data)"
        return
    fi
    
    # Analyze execution records
    local excellent_count=0
    local good_count=0
    local total_count=0
    local avg_batch_size=0
    local successful_batch_sizes=""
    
    for record in "$FEEDBACK_DIR"/execution-*.json; do
        [ -f "$record" ] || continue
        
        local classification=$(grep '"classification":' "$record" | cut -d'"' -f4)
        local batch_size=$(grep '"batch_size":' "$record" | cut -d':' -f2 | cut -d',' -f1 | xargs)
        
        total_count=$((total_count + 1))
        avg_batch_size=$((avg_batch_size + batch_size))
        
        case "$classification" in
            "excellent")
                excellent_count=$((excellent_count + 1))
                successful_batch_sizes="$successful_batch_sizes $batch_size"
                ;;
            "good")
                good_count=$((good_count + 1))
                successful_batch_sizes="$successful_batch_sizes $batch_size"
                ;;
        esac
    done
    
    if [ "$total_count" -gt 0 ]; then
        avg_batch_size=$((avg_batch_size / total_count))
    fi
    
    # Calculate confidence score
    local confidence_score=0
    if [ "$total_count" -gt 0 ]; then
        confidence_score=$(((excellent_count + good_count) * 100 / total_count))
    fi
    
    # Find most common successful batch size
    local recommended_batch_size="$avg_batch_size"
    if [ -n "$successful_batch_sizes" ]; then
        recommended_batch_size=$(echo "$successful_batch_sizes" | tr ' ' '\n' | sort -n | uniq -c | sort -nr | head -1 | awk '{print $2}')
    fi
    
    # Generate recommendations
    echo "Based on $total_count execution(s):"
    echo "- Recommended batch size: $recommended_batch_size agents"
    echo "- Success rate: $((excellent_count + good_count))/$total_count executions"
    echo "- Confidence score: $confidence_score%"
    
    if [ "$confidence_score" -ge 80 ]; then
        echo "- Confidence: High"
    elif [ "$confidence_score" -ge 60 ]; then
        echo "- Confidence: Medium"
    else
        echo "- Confidence: Low (more data needed)"
    fi
    
    # Specific recommendations
    echo ""
    echo "Specific Recommendations:"
    if [ "$excellent_count" -gt 2 ]; then
        echo "✅ Current configuration is working well"
        echo "💡 Consider slightly increasing batch size for better throughput"
    elif [ "$good_count" -gt 1 ]; then
        echo "🔧 Current configuration is acceptable"
        echo "💡 Monitor memory usage and consider optimization"
    else
        echo "⚠️  Performance issues detected"
        echo "💡 Reduce batch size and memory per agent"
        echo "💡 Check system resources and close other applications"
    fi
}

# Function to suggest optimal configuration for a specific workload
function suggest_configuration() {
    local stream_count="$1"
    local workload_type="${2:-general}"
    
    echo "Configuration Suggestion for $stream_count streams ($workload_type workload)"
    echo "======================================================================="
    
    # Base recommendations from feedback
    local base_batch_size=8
    local base_memory_per_agent=8
    
    # Adjust based on historical patterns if available
    if [ -f "$FEEDBACK_DIR/patterns.json" ]; then
        # In production, would parse JSON for optimal values
        # For now, using simple heuristics
        
        if [ "$stream_count" -le 4 ]; then
            echo "Small workload detected ($stream_count streams)"
            echo "- Suggested batch size: $stream_count (single batch)"
            echo "- Memory per agent: 8GB"
            echo "- Expected execution time: 15-30 minutes"
        elif [ "$stream_count" -le 12 ]; then
            echo "Medium workload detected ($stream_count streams)"
            echo "- Suggested batch size: 8 agents"
            echo "- Number of batches: $(((stream_count + 7) / 8))"
            echo "- Memory per agent: 8GB"
            echo "- Expected execution time: 30-60 minutes"
        else
            echo "Large workload detected ($stream_count streams)"
            echo "- Suggested batch size: 6 agents (reduced for stability)"
            echo "- Number of batches: $(((stream_count + 5) / 6))"
            echo "- Memory per agent: 6GB (reduced for stability)"
            echo "- Expected execution time: 60+ minutes"
        fi
    fi
    
    # System-specific recommendations
    echo ""
    echo "System Recommendations:"
    echo "- Close unnecessary applications"
    echo "- Ensure at least 20GB free memory before starting"
    echo "- Monitor system during execution"
    echo "- Consider running during off-peak hours for large workloads"
}

# Function to analyze memory trends
function analyze_trends() {
    echo "Memory Usage Trends Analysis"
    echo "============================"
    
    if [ ! -d "$FEEDBACK_DIR" ]; then
        echo "No feedback data available"
        return
    fi
    
    local recent_executions=0
    local memory_issues=0
    local avg_peak_memory=0
    local trend_direction="stable"
    
    # Analyze recent execution records (last 10)
    for record in $(ls -t "$FEEDBACK_DIR"/execution-*.json 2>/dev/null | head -10); do
        [ -f "$record" ] || continue
        
        recent_executions=$((recent_executions + 1))
        
        local peak_memory=$(grep '"peak_memory_usage":' "$record" | cut -d':' -f2 | cut -d',' -f1 | xargs)
        local retries=$(grep '"retries_needed":' "$record" | cut -d':' -f2 | cut -d',' -f1 | xargs)
        
        avg_peak_memory=$((avg_peak_memory + peak_memory))
        
        if [ "$retries" -gt 0 ]; then
            memory_issues=$((memory_issues + 1))
        fi
    done
    
    if [ "$recent_executions" -gt 0 ]; then
        avg_peak_memory=$((avg_peak_memory / recent_executions))
    fi
    
    echo "Recent Executions: $recent_executions"
    echo "Average Peak Memory: $avg_peak_memory%"
    echo "Executions with Memory Issues: $memory_issues"
    echo "Memory Issue Rate: $((memory_issues * 100 / (recent_executions > 0 ? recent_executions : 1)))%"
    
    # Trend analysis
    if [ "$memory_issues" -gt $((recent_executions / 2)) ]; then
        echo "Trend: ⬆️ Increasing memory pressure"
        echo "Recommendation: Reduce batch sizes and memory allocation"
    elif [ "$avg_peak_memory" -lt 70 ]; then
        echo "Trend: ⬇️ Memory usage is low"
        echo "Recommendation: Consider increasing batch sizes for better performance"
    else
        echo "Trend: ➡️ Memory usage is stable"
        echo "Recommendation: Current configuration appears optimal"
    fi
}

# Main execution
function main() {
    case "$ACTION" in
        "init")
            init_feedback_system
            ;;
        "record")
            if [ $# -lt 7 ]; then
                echo "Usage: $0 record <epic-name> <batch-size> <total-streams> <success-rate> <peak-memory> <execution-time>"
                exit 1
            fi
            record_execution_pattern "$EPIC_NAME" "$3" "$4" "$5" "$6" "$7"
            ;;
        "recommend")
            generate_recommendations
            ;;
        "suggest")
            if [ -z "$3" ]; then
                echo "Usage: $0 suggest <epic-name> <stream-count> [workload-type]"
                exit 1
            fi
            suggest_configuration "$3" "$4"
            ;;
        "trends")
            analyze_trends
            ;;
        *)
            echo "Usage: $0 <action> [epic-name] [additional-params]"
            echo ""
            echo "Actions:"
            echo "  init            - Initialize feedback system"
            echo "  record          - Record execution pattern"
            echo "  recommend       - Generate recommendations based on history"
            echo "  suggest         - Suggest configuration for specific workload"
            echo "  trends          - Analyze memory usage trends"
            exit 1
            ;;
    esac
}

main "$@"