---
created: 2025-08-25T22:25:24Z
last_updated: 2025-08-26T18:58:39Z
version: 1.2
author: Claude Code PM System
---

# Technical Context

## Technology Stack

### Primary Technologies
- **Shell/Bash**: System automation and command implementation
- **Markdown**: Documentation and content format
- **Git**: Version control and worktree management
- **GitHub CLI (gh)**: Repository integration and API access
- **YAML**: Configuration and frontmatter
- **Node.js V8**: Memory management and heap optimization
- **JSON**: Configuration state and pattern storage

### Development Environment
- **Platform Support**: macOS, Linux (bash-compatible environments)
- **Required Tools**: git, gh (GitHub CLI), bash
- **Optional Tools**: tree (for directory visualization)

## Dependencies

### Core Dependencies
1. **GitHub CLI (gh)**
   - Purpose: Repository integration and API access
   - Installation: Automatic via `/pm:init` command
   - Version: Latest stable
   - Critical for: Issue management, PR creation, repository operations

2. **gh-sub-issue Extension**
   - Purpose: Parent-child issue relationships
   - Repository: https://github.com/yahsan2/gh-sub-issue
   - Installation: Automatic via `/pm:init` command
   - Fallback: Task list format if extension unavailable

3. **Git**
   - Purpose: Version control and worktree operations
   - Version: Modern git with worktree support
   - Critical for: Branch operations, parallel development

### System Dependencies
- **Bash Shell**: Command execution and script automation
- **Standard Unix Tools**: find, grep, sed, awk, cat, ls, etc.
- **Date Command**: UTC timestamp generation
- **File System**: Read/write access to project directory
- **Update System**: Built-in versioning and backup/restore capabilities
- **Memory Monitoring**: System memory assessment and resource tracking
- **Process Management**: Agent lifecycle and cleanup utilities

## Architecture Patterns

### Command Pattern
- Commands defined as markdown files with specifications
- Implementation through Claude Code's command system
- Consistent parameter handling and validation
- Error handling and user feedback standards

### Agent Pattern
- Specialized agents for different domains (code, files, tests, parallel work)
- Context isolation to prevent pollution
- Task-specific expertise and optimization
- Coordinated execution through main controller

### Frontmatter Pattern
- YAML frontmatter for metadata consistency
- Standardized fields: created, last_updated, version, author
- Real datetime handling (never placeholders)
- Version management for change tracking

### Worktree Pattern
- Isolated development environments for parallel work
- Branch-per-epic or branch-per-feature
- Clean merge strategy for completed work
- Conflict prevention through isolation

### Memory Management Pattern
- Dynamic batching based on available system memory
- Memory-aware agent spawning with configurable limits
- Real-time resource monitoring and cleanup verification
- Learning system for optimization based on usage patterns
- Node.js heap optimization with V8 flags

## File Formats

### Markdown (.md)
- **Purpose**: All documentation and content
- **Standard**: CommonMark with GitHub Flavored Markdown
- **Frontmatter**: YAML metadata block
- **Cross-references**: Relative path linking within `.claude/`

### JSON (.json)
- **Purpose**: Configuration files (`settings.local.json`)
- **Standard**: Valid JSON with comments where supported
- **Usage**: Command permissions, system settings

### Shell Scripts (.sh)
- **Purpose**: Automation and utility operations
- **Standard**: Bash-compatible shell scripts
- **Location**: `.claude/scripts/` directory
- **Pattern**: Descriptive names, error handling, documentation headers

## Integration Points

### GitHub Integration
- **API Access**: Through gh CLI tool
- **Authentication**: GitHub token via gh auth
- **Operations**: Issue creation, updates, PR management
- **Labels**: Automated labeling for organization
- **Comments**: Progress updates and communication

### Git Integration
- **Worktrees**: Parallel development isolation
- **Branches**: Feature/epic branch management
- **Commits**: Automated commits with consistent messages
- **Merging**: Clean merge strategies for completed work

### Claude Code Integration
- **Command System**: Native command registration and execution
- **Tool Access**: Bash, file operations, git commands
- **Context Management**: File-based context preservation
- **Agent Coordination**: Multi-agent task execution

## Performance Considerations

### Context Optimization
- **Agent Specialization**: Prevents context pollution in main thread
- **File-based Context**: Persistent knowledge across sessions
- **Selective Loading**: Load only relevant context per task
- **Context Compression**: Summarized information in specialized formats

### Execution Efficiency
- **Memory-Aware Parallel Processing**: 8-12 agents with dynamic batching
- **Resource-Based Scheduling**: Spawn capacity calculated from available memory
- **Local-first Operations**: Work locally, sync when ready
- **Batch Operations**: Group related operations for efficiency
- **Memory Optimization**: V8 heap tuning and garbage collection optimization
- **Caching**: Avoid redundant operations and API calls

### Scalability
- **Memory-Constrained Scaling**: Maximum 80GB of 96GB system memory usage
- **Modular Architecture**: Add new agents and commands independently
- **Directory Organization**: Logical separation prevents conflicts
- **Template System**: Reusable patterns for consistent implementation
- **Configuration Management**: Environment-specific settings with memory tuning

## Security Considerations

### Access Control
- **GitHub Authentication**: Secure token-based auth via gh CLI
- **File Permissions**: Standard file system permissions
- **Script Execution**: Only trusted scripts in `.claude/scripts/`
- **Input Validation**: Parameter validation in all commands

### Data Handling
- **Sensitive Information**: Never commit tokens or secrets
- **Repository Access**: Respects GitHub repository permissions
- **Local Storage**: Context files stored in project directory
- **Clean Separation**: Local planning vs. remote tracking

## Development Workflow

### Local Development
1. **Context Loading**: Prime context at session start
2. **Planning**: Create PRDs and epics locally
3. **Task Breakdown**: Decompose epics into actionable tasks
4. **Implementation**: Execute with specialized agents
5. **Synchronization**: Push updates to GitHub when ready

### GitHub Workflow
1. **Issue Creation**: Sync epics and tasks as GitHub issues
2. **Progress Tracking**: Update issues with progress comments
3. **PR Management**: Create PRs for completed work
4. **Review Process**: Standard GitHub review workflow
5. **Completion**: Close issues and merge PRs

### Quality Assurance
- **Validation Commands**: Built-in system integrity checks
- **Error Handling**: Graceful failure with helpful messages
- **Documentation**: Comprehensive documentation for all components
- **Testing**: Manual testing workflows via test-runner agent

## Extension Points

### Adding New Agents
- Create agent definition in `.claude/agents/`
- Define agent capabilities and specialization
- Integrate with parallel-worker coordination
- Document agent purpose and usage patterns

### Adding New Commands
- Create command specification in appropriate subdirectory
- Define parameters, validation, and implementation
- Add to command registry and help system
- Include error handling and user feedback

### Adding New Rules
- Create rule file in `~/.claude/rules/`
- Define operational guidelines and constraints
- Reference from relevant commands and agents
- Maintain consistency with existing patterns

This technical foundation enables sophisticated project management while maintaining simplicity and reliability.

## Update History
- 2025-08-26T18:58:39Z: Added memory management architecture pattern, Node.js V8 optimization, memory-aware execution efficiency, resource monitoring dependencies