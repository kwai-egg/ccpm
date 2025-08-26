---
created: 2025-08-25T22:25:24Z
last_updated: 2025-08-25T23:57:41Z
version: 1.1
author: Claude Code PM System
---

# System Patterns

## Architectural Patterns

### Command Pattern Implementation
The system uses a comprehensive command pattern where:
- **Commands** are defined as markdown specifications
- **Execution** happens through Claude Code's native command system
- **Validation** occurs at both parameter and system levels
- **Error Handling** provides consistent user feedback
- **Documentation** is embedded in command definitions

**Example Structure:**
```markdown
# Command: /pm:epic-start
## Purpose
Launches parallel execution for an epic across multiple worktrees

## Parameters
- epic_name: Required string matching existing epic

## Implementation
[Detailed execution steps]
```

### Agent Specialization Pattern
Different agents handle specific domains to optimize context usage:

- **code-analyzer**: Deep code analysis, bug detection, logic tracing
- **file-analyzer**: File content summarization and extraction
- **test-runner**: Test execution and result analysis
- **parallel-worker**: Multi-stream coordination and execution

**Benefits:**
- Prevents context pollution in main conversation
- Enables domain expertise optimization
- Allows parallel execution of different task types
- Maintains clean separation of concerns

### Context Preservation Pattern
Persistent knowledge management through file-based context:

```
.claude/context/
├── progress.md           # Current state and recent work
├── project-structure.md  # Directory organization
├── tech-context.md      # Technical stack and dependencies
└── [additional context] # Domain-specific context files
```

**Key Principles:**
- **Immutable Creation**: `created` timestamp never changes
- **Real Timestamps**: Always use actual system time
- **Version Tracking**: Increment version for significant updates
- **Selective Updates**: Only modify sections that actually changed

### Worktree Isolation Pattern
Parallel development through git worktree management:

```
project/
├── main/                 # Main development directory
├── epic-feature-a/       # Isolated worktree for epic A
├── epic-feature-b/       # Isolated worktree for epic B
└── epic-feature-c/       # Isolated worktree for epic C
```

**Advantages:**
- **Conflict Prevention**: Complete isolation of parallel work
- **Clean Merges**: Controlled integration when ready
- **Context Switching**: Easy switching between different epics
- **Resource Efficiency**: Shared git history, separate working directories

### Update System Pattern
Comprehensive update management with versioning and backup/restore:

```
.ccpm-backups/
├── backup-2025-08-25-23-45/  # Timestamped backup snapshots
├── backup-2025-08-25-22-30/
└── current -> backup-2025-08-25-23-45/
```

**Key Components:**
- **Version Tracking**: Semantic versioning in `.claude/VERSION`
- **Change Logging**: Comprehensive changelog in `.claude/CHANGELOG.md`
- **Backup Management**: Automatic backups before updates
- **Rollback Capability**: Restore previous system states
- **Update Validation**: Verify system integrity after updates

**Benefits:**
- **Safe Updates**: Rollback capability prevents system breakage
- **Change Tracking**: Complete audit trail of system modifications
- **Configuration Management**: Layered settings with project overrides
- **Automated Maintenance**: Self-managing backup retention

## Data Flow Patterns

### Local-First Development
All work begins locally and syncs to GitHub explicitly:

```mermaid
graph LR
    A[Local Planning] --> B[Task Breakdown]
    B --> C[Implementation]
    C --> D[GitHub Sync]
    D --> E[Team Visibility]
```

**Benefits:**
- **Fast Iteration**: No network dependency for planning
- **Controlled Sync**: Push updates when ready
- **Offline Capability**: Work continues without connectivity
- **Clean History**: Only meaningful updates reach GitHub

### Progressive Decomposition
Ideas break down through structured refinement:

```
Idea → PRD → Epic → Tasks → Issues → Implementation → Code
```

**Each Stage Adds:**
- **PRD**: User stories, success criteria, constraints
- **Epic**: Technical approach, architecture decisions
- **Tasks**: Concrete implementation steps, acceptance criteria
- **Issues**: GitHub tracking, team coordination
- **Implementation**: Actual code changes
- **Code**: Production-ready software

### Context Propagation
Information flows through the system hierarchically:

```
Project Context → Epic Context → Task Context → Implementation Context
```

**Inheritance Rules:**
- Lower levels inherit from higher levels
- Specific context overrides general context
- Updates propagate upward (task completion updates epic)
- Context isolation prevents pollution

## Error Handling Patterns

### Graceful Degradation
System continues operating when optional components fail:

- **GitHub CLI Missing**: Inform user, provide manual steps
- **Extensions Unavailable**: Fall back to basic functionality
- **Network Issues**: Continue with local operations
- **Permission Problems**: Clear error messages with solutions

### Fail-Fast Validation
Critical requirements checked immediately:

```bash
# Example preflight checks
test -d .git || error "Not a git repository"
gh auth status || error "GitHub authentication required"
test -w .claude/ || error "Cannot write to .claude directory"
```

### Progressive Error Recovery
Errors provide actionable recovery steps:

```
❌ Cannot create context directory. Check permissions.
💡 Try: chmod 755 .claude/
💡 Or: sudo chown $USER .claude/
```

## Synchronization Patterns

### Explicit Sync Strategy
Synchronization happens on command, not automatically:

- **Benefits**: Predictable behavior, no surprises
- **Commands**: `/pm:epic-sync`, `/pm:issue-sync`, `/pm:sync`
- **Granularity**: Sync individual components or everything
- **Control**: User decides when to share progress

### Bidirectional Sync
Changes can originate locally or on GitHub:

```bash
Local Changes → GitHub   # /pm:epic-sync feature-name
GitHub Changes → Local   # /pm:import
Full Sync ↔ GitHub      # /pm:sync
```

### Conflict Resolution
Clear ownership and resolution strategies:

- **Local Authority**: Local files are source of truth during development
- **GitHub Authority**: GitHub issues are source of truth for team coordination
- **Manual Resolution**: Conflicts require explicit user decision
- **Backup Strategy**: Original state preserved during sync operations

## Coordination Patterns

### Multi-Agent Coordination
Parallel agents work together through defined protocols:

```bash
# Main thread orchestrates
/pm:epic-start feature-name

# Spawns multiple specialized agents
Agent 1: Database schema changes
Agent 2: API endpoint implementation  
Agent 3: UI component development
Agent 4: Test suite creation
Agent 5: Documentation updates

# Coordination through shared git history
# Each agent commits progress independently
# Main thread merges when all agents complete
```

### State Management
System state tracked through multiple channels:

- **File System**: Local task and epic files
- **Git History**: Commit messages and branch state
- **GitHub Issues**: Remote tracking and team coordination
- **Context Files**: Project knowledge and progress

### Communication Patterns
Information sharing between components:

- **Command Output**: Structured status updates
- **File Updates**: Context and task file modifications
- **GitHub Comments**: Progress updates for team visibility
- **Git Commits**: Implementation progress tracking

## Quality Assurance Patterns

### Validation Layers
Multiple validation points ensure system integrity:

1. **Parameter Validation**: Command inputs checked immediately
2. **System Validation**: Dependencies and prerequisites verified
3. **Content Validation**: File format and structure verified
4. **Integration Validation**: GitHub sync and git operations verified

### Testing Strategy
Comprehensive testing through specialized agents:

- **Manual Testing**: Through test-runner agent
- **Integration Testing**: Full workflow validation
- **System Testing**: Command and agent functionality
- **Documentation Testing**: Example validation and accuracy

### Monitoring and Observability
System health tracked through multiple indicators:

- **Command Success**: All commands report success/failure
- **File Integrity**: Context files maintain valid format
- **Sync Status**: GitHub integration monitored
- **Error Tracking**: Problems logged with actionable solutions

## Extension Patterns

### Plugin Architecture
New functionality added through defined extension points:

```
.claude/
├── agents/          # Add new specialized agents
├── commands/        # Add new command categories
├── rules/           # Add new operational rules
├── scripts/         # Add new automation utilities
└── templates/       # Add new content templates
```

### Template System
Reusable patterns for consistent implementation:

- **Command Templates**: Consistent command structure
- **Agent Templates**: Standard agent capabilities
- **Content Templates**: PRD, epic, and task formats
- **Documentation Templates**: Consistent documentation patterns

### Configuration Management
Flexible configuration through layered settings:

- **System Defaults**: Built-in sensible defaults
- **Project Settings**: Project-specific overrides
- **User Settings**: Personal preference overrides
- **Environment Settings**: Runtime configuration

This pattern system enables sophisticated project management while maintaining simplicity, reliability, and extensibility.