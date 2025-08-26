---
created: 2025-08-25T22:25:24Z
last_updated: 2025-08-26T18:58:39Z
version: 1.2
author: Claude Code PM System
---

# Project Structure

## Root Directory Organization

```
ccpm/
├── .claude/                # Core system directory
├── .git/                   # Git repository data
├── .gitignore             # Git ignore patterns
├── .vscode/               # VS Code workspace settings
│   └── settings.json     # Editor configuration
└── [project files]       # Main project content
```

**Recent Changes:**
- **Memory Optimization System**: Added comprehensive memory management infrastructure
- **New Directories**: agent-pool/, env/, memory-feedback/ for resource management
- **Enhanced Scripts**: 8 new memory management scripts in scripts/pm/
- **Configuration Enhancement**: Memory management settings in .claude-pm.yaml

## Core System Architecture (.claude/)

### Primary Directories

```
.claude/
├── agent-pool/            # Agent process pooling system
├── agents/                # Specialized task agents
├── commands/              # Command definitions and implementations
├── context/               # Project context documentation
├── env/                   # Environment configuration files
├── epics/                 # PM workspace for epic management
├── memory-feedback/       # Memory optimization feedback system
├── prds/                  # Product Requirements Documents
├── rules/                 # System operation rules
├── scripts/               # Automation and utility scripts
├── templates/             # Reusable templates
├── .claude-pm.yaml        # Project management configuration (Enhanced)
├── CHANGELOG.md           # System change history
├── MEMORY-OPTIMIZATION-SUMMARY.md # Memory system documentation
├── VERSION                # Current system version
└── settings.local.json    # Local configuration overrides
```

### Agent System (agents/)

```
agents/
├── code-analyzer.md       # Code analysis and bug detection
├── file-analyzer.md       # File content analysis and summarization
├── parallel-worker.md     # Multi-stream parallel execution
└── test-runner.md         # Test execution and analysis
```

**Purpose**: Specialized agents for context optimization and task execution
**Pattern**: Each agent handles specific domain expertise with isolated context

### Command System (commands/)

```
commands/
├── context/               # Context management commands
│   ├── create.md         # Initialize project context
│   ├── prime.md          # Load context for new sessions
│   └── update.md         # Refresh existing context
├── pm/                   # Project management commands
│   ├── epic-*.md         # Epic management commands
│   ├── issue-*.md        # Issue workflow commands
│   ├── prd-*.md          # PRD lifecycle commands
│   ├── update*.md        # Update system commands
│   │   ├── update.md     # Main update command
│   │   ├── update-check.md # Update availability check
│   │   ├── update-init.md  # Initialize update system
│   │   ├── update-rollback.md # Rollback updates
│   │   └── update-status.md   # Update system status
│   └── epic-retry.md     # Epic retry functionality
└── testing/
    └── prime.md          # Test environment setup
```

**Purpose**: Comprehensive command system for project lifecycle management
**Pattern**: Commands organized by functional area with detailed implementation specs

### Context System (context/)

```
context/
├── README.md             # Context system overview
├── progress.md           # Current project status and recent work
├── project-structure.md  # This file - directory organization
├── tech-context.md       # Dependencies and technical stack
├── system-patterns.md    # Architectural patterns and design decisions
├── product-context.md    # Product requirements and user context
├── project-brief.md      # Project scope and objectives
├── project-overview.md   # High-level feature summary
├── project-vision.md     # Long-term strategic direction
└── project-style-guide.md # Coding standards and conventions
```

**Purpose**: Persistent knowledge base for project understanding
**Pattern**: Comprehensive documentation enabling agent onboarding and context preservation

### Rules System (rules/)

```
rules/
├── agent-coordination.md   # Multi-agent coordination protocols
├── branch-operations.md    # Git branch management standards
├── datetime.md            # Date/time handling requirements
├── frontmatter-operations.md # Frontmatter management rules
├── github-operations.md    # GitHub API usage guidelines
├── standard-patterns.md    # Common development patterns
├── strip-frontmatter.md   # Frontmatter processing rules
├── test-execution.md      # Testing workflow standards
├── use-ast-grep.md        # AST-based code search guidelines
└── worktree-operations.md  # Git worktree management
```

**Purpose**: Operational guidelines ensuring consistent system behavior
**Pattern**: Domain-specific rules for complex operations and integrations

### Scripts System (scripts/)

```
scripts/
├── pm/                   # Project management automation (25+ scripts)
│   ├── coordination-*.sh # Multi-agent coordination utilities
│   │   ├── coordination-block.sh    # Coordination blocking
│   │   ├── coordination-check.sh    # Check coordination state  
│   │   ├── coordination-init.sh     # Initialize coordination
│   │   └── coordination-memory.sh   # Memory-aware coordination
│   ├── memory-*.sh       # Memory optimization system
│   │   ├── memory-monitor.sh        # System memory monitoring
│   │   ├── memory-env.sh           # Environment configuration  
│   │   ├── memory-retry.sh         # Memory-based retry logic
│   │   └── memory-feedback.sh      # Learning and optimization
│   ├── agent-pool.sh     # Agent process pooling
│   ├── coordinator-setup.sh # Coordinator configuration
│   ├── start-coordinator.sh # Memory-optimized startup
│   ├── update-*.sh       # Update system scripts
│   │   ├── update-backup.sh        # Create system backups
│   │   ├── update-check.sh         # Check for updates
│   │   ├── update-init.sh          # Initialize update system
│   │   ├── update-restore.sh       # Restore from backup
│   │   └── update.sh               # Main update script
│   ├── github-utils.sh   # GitHub integration utilities
│   ├── help.sh          # Help system
│   └── create-guidance-template.sh # Template generation
└── test-and-log.sh      # Test execution utilities
```

**Purpose**: Automation utilities supporting command implementations
**Pattern**: Shell scripts handling complex system operations

### Templates System (templates/)

```
templates/
└── stream-guidance-template.md # Template for development guidance
```

**Purpose**: Reusable templates for consistent workflow and documentation
**Pattern**: Markdown templates with placeholder content for quick initialization

### Memory Optimization System

```
.claude/
├── agent-pool/            # Agent process pooling
│   └── pool-state.json   # Pool state and metrics
├── env/                  # Environment configuration
│   ├── coordinator.env   # Coordinator NODE_OPTIONS (16GB heap)
│   └── agent.env        # Agent NODE_OPTIONS (8GB heap)
└── memory-feedback/      # Learning and optimization system
    └── patterns.json    # Historical execution patterns
```

**Purpose**: Comprehensive memory management for parallel agent execution
**Pattern**: Resource monitoring, dynamic batching, and optimization feedback

## File Naming Conventions

### Context Files
- Use descriptive kebab-case names (`project-structure.md`)
- Include `.md` extension for all documentation
- Maintain consistent frontmatter across all files

### Command Files  
- Organize by functional area in subdirectories
- Use descriptive names indicating purpose (`epic-decompose.md`)
- Include full implementation specifications

### Epic and Task Files
- Tasks start as numbered files: `001.md`, `002.md`
- Renamed to issue IDs after GitHub sync: `1234.md`
- Epic name becomes directory name: `/epics/feature-name/`

## Key Patterns

### Documentation Structure
- All files include YAML frontmatter with metadata
- Consistent markdown formatting and section organization
- Cross-references use relative paths within `.claude/`

### Workflow Integration
- Local files serve as source of truth during development
- GitHub synchronization happens explicitly via commands
- Separation between local planning and remote tracking

### Context Preservation
- Context files maintain project memory across sessions
- Agent specialization reduces context pollution
- Modular organization enables targeted updates

## Growth Patterns

### Adding New Features
1. Create PRD in `/prds/`
2. Generate epic in `/epics/feature-name/`
3. Break into tasks within epic directory
4. Sync to GitHub as issues
5. Execute with specialized agents

### System Extension
- New agents added to `/agents/` directory
- New commands organized by functional area
- Rules added for complex operational requirements
- Scripts support automation needs

This structure enables scalable project management while maintaining clean separation of concerns and comprehensive documentation.

## Update History
- 2025-08-26T18:58:39Z: Added memory optimization system directories (agent-pool/, env/, memory-feedback/), 8 new memory management scripts, enhanced script organization