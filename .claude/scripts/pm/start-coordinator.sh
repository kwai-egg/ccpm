#!/bin/bash
# Coordinator startup script with memory optimization
# This script should be sourced, not executed

echo "Starting Claude Code PM Coordinator with memory optimization..."

# Apply coordinator environment
if [ -f "~/.claude/scripts/pm/coordinator-setup.sh" ]; then
    source .claude/scripts/pm/coordinator-setup.sh apply
else
    echo "❌ Coordinator setup script not found"
    exit 1
fi

# Initialize memory monitoring
if [ -f "~/.claude/scripts/pm/memory-monitor.sh" ]; then
    echo "Current system memory status:"
    .claude/scripts/pm/memory-monitor.sh usage
    echo ""
fi

# Initialize agent pool
if [ -f "~/.claude/scripts/pm/agent-pool.sh" ]; then
    .claude/scripts/pm/agent-pool.sh init
fi

# Initialize memory feedback system
if [ -f "~/.claude/scripts/pm/memory-feedback.sh" ]; then
    .claude/scripts/pm/memory-feedback.sh init
fi

echo "✅ Claude Code PM Coordinator ready with memory optimization"
echo "   Use '/pm:epic-start <epic-name>' to begin parallel execution"
