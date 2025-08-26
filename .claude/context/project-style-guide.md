---
created: 2025-08-25T22:25:24Z
last_updated: 2025-08-25T23:57:41Z
version: 1.0
author: Claude Code PM System
---

# Project Style Guide

## Documentation Standards

### Markdown Format
**File Structure**:
```yaml
---
created: YYYY-MM-DDTHH:MM:SSZ     # Real UTC timestamp, never placeholder
last_updated: YYYY-MM-DDTHH:MM:SSZ # Real UTC timestamp, updated on changes  
version: X.Y                      # Semantic versioning (1.0, 1.1, 2.0, etc.)
author: Claude Code PM System     # Consistent author attribution
---

# Document Title

## Section Structure
- Use ## for main sections
- Use ### for subsections
- Use #### sparingly for detailed breakdowns
```

**Content Guidelines**:
- **Concise but Complete**: Provide sufficient detail without unnecessary verbosity
- **Action-Oriented**: Focus on what needs to be done, not just what exists
- **Example-Rich**: Include code examples, command samples, and usage patterns
- **Cross-Referenced**: Link to related documents using relative paths

### Frontmatter Standards
**Required Fields**:
- `created`: UTC timestamp when file first created (never changes)
- `last_updated`: UTC timestamp of last significant modification
- `version`: Semantic version number (increment for substantial changes)
- `author`: Always "Claude Code PM System" for consistency

**Version Management**:
- `1.0`: Initial version
- `1.1`: Minor updates, clarifications, small additions
- `2.0`: Major restructuring, significant content changes
- `2.1`: Minor updates to major revision

**Timestamp Format**:
- Always use actual system time via `date -u +"%Y-%m-%dT%H:%M:%SZ"`
- Never use placeholders like "YYYY-MM-DD" or "TBD"
- Update `last_updated` only for meaningful content changes

## File Naming Conventions

### Context Files
- Use descriptive kebab-case names: `project-structure.md`
- Avoid abbreviations: `product-context.md` not `prod-ctx.md`
- Include `.md` extension for all documentation
- Group related concepts: `project-*` for project-level context

### Command Files
- Organize by functional area in subdirectories
- Use descriptive action names: `epic-decompose.md`, `issue-sync.md`  
- Include full command specification in filename: `pm-epic-start.md`
- Maintain consistent naming patterns within categories

### Task and Epic Files
- Tasks start numbered during decomposition: `001.md`, `002.md`
- Rename to GitHub issue IDs after sync: `1234.md`
- Epic directories use feature names: `/epics/user-authentication/`
- Use kebab-case for multi-word feature names

### Script Files
- Use `.sh` extension for shell scripts
- Descriptive names indicating purpose: `coordination-check.sh`
- Group by functionality in subdirectories: `/scripts/pm/`
- Include action in filename: `create-guidance-template.sh`

## Command Structure Standards

### Command Definition Format
```markdown
# Command: /pm:command-name

## Purpose
Brief description of what this command accomplishes

## Parameters
- parameter_name: Required/Optional type - Description
- another_param: Optional string - Additional parameter

## Prerequisites
- List of required conditions
- Dependencies that must be satisfied

## Implementation
Detailed step-by-step implementation process

## Examples
```bash
/pm:command-name param1 param2
```

## Error Handling
Common failure scenarios and recovery steps

## Related Commands
- `/pm:related-command` - Brief description
```

### Parameter Documentation
- **Required vs Optional**: Clearly mark parameter requirements
- **Type Information**: string, integer, boolean, path, etc.
- **Default Values**: Document defaults for optional parameters
- **Validation Rules**: Specify acceptable values and formats

### Error Message Standards
```markdown
❌ Error: Clear description of what went wrong
💡 Try: Specific action to resolve the issue
💡 Or: Alternative resolution approach
```

**Error Message Principles**:
- Start with ❌ for errors, ⚠️ for warnings
- Provide specific, actionable recovery steps
- Include relevant context (file names, commands, etc.)
- Offer multiple resolution paths when possible

## Code and Script Standards

### Shell Script Style
```bash
#!/bin/bash
# Script: script-name.sh
# Purpose: Brief description of script function
# Usage: ./script-name.sh [parameters]

set -e  # Exit on error
set -u  # Error on undefined variables

# Function definitions
function main() {
    # Main script logic
}

# Error handling
function error_exit() {
    echo "❌ Error: $1" >&2
    exit 1
}

# Call main function
main "$@"
```

**Script Standards**:
- Include descriptive header comments
- Use proper error handling with meaningful messages
- Validate inputs and prerequisites
- Provide usage information for complex scripts

### Command Examples
```bash
# Good: Clear, specific examples
/pm:epic-start user-authentication
/pm:issue-sync 1234
/pm:next

# Bad: Generic placeholders
/pm:epic-start <epic-name>
/pm:issue-sync <issue-id>
```

**Example Standards**:
- Use realistic, specific examples rather than generic placeholders
- Show both success and error scenarios
- Include context about when to use each command
- Demonstrate parameter combinations and variations

## Content Organization Patterns

### Directory Structure
```
.claude/
├── agents/           # One file per agent, descriptive names
├── commands/         # Organized by functional area
│   ├── context/     # Context management commands
│   ├── pm/          # Project management commands
│   └── testing/     # Test-related commands
├── context/          # Project context documentation
├── rules/           # Operational guidelines and constraints
├── scripts/         # Automation utilities
└── templates/       # Reusable content templates
```

### Section Organization Within Files
1. **Purpose/Overview**: What this addresses
2. **Prerequisites**: What's needed before using
3. **Implementation**: How it works  
4. **Usage Examples**: Practical application
5. **Error Handling**: What can go wrong and how to fix it
6. **Related Information**: Cross-references and next steps

### Cross-Reference Patterns
- Use relative paths: `../rules/branch-operations.md`
- Link to specific sections: `../context/progress.md#current-status`
- Maintain consistent link text: `[branch operations rules](../rules/branch-operations.md)`
- Verify links remain valid as files move or change

## Quality Standards

### Content Quality
- **Accuracy**: All information must be current and correct
- **Completeness**: Cover all essential aspects of the topic
- **Clarity**: Write for the intended audience (developers, team leads)
- **Actionability**: Provide specific steps and examples
- **Maintainability**: Structure for easy updates and modifications

### Review Criteria
- **Technical Accuracy**: Commands and examples work as documented
- **Consistency**: Follows established patterns and conventions
- **Completeness**: Addresses all relevant use cases and scenarios
- **Readability**: Clear structure and language appropriate for audience
- **Integration**: Fits well with existing documentation and workflows

### Update Management
- **Version Control**: Increment versions for significant changes
- **Timestamp Accuracy**: Update `last_updated` for meaningful changes only
- **Change Documentation**: Note significant updates in file or commit messages
- **Cross-Reference Updates**: Update related files when making changes
- **Validation**: Verify examples and instructions after updates

## Communication Style

### Tone and Voice
- **Professional but Approachable**: Technical accuracy with human warmth
- **Action-Oriented**: Focus on what users need to do
- **Confident**: Provide definitive guidance when appropriate
- **Humble**: Acknowledge limitations and alternative approaches

### Language Guidelines
- **Active Voice**: "Run the command" not "The command should be run"
- **Present Tense**: "The system creates" not "The system will create"
- **Specific Terms**: Use precise technical terminology consistently
- **Inclusive Language**: Write for diverse, global development teams

### Formatting Conventions
- **Bold**: For **important concepts** and **key terms**
- **Italic**: For *emphasis* and *variable names*
- **Code**: For `commands`, `file-names`, and `technical-terms`
- **Lists**: Use consistent bullet points and numbering
- **Tables**: For structured comparisons and feature matrices

This style guide ensures consistency, quality, and maintainability across all project documentation while supporting effective collaboration and knowledge preservation.