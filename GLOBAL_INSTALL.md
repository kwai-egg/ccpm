# Global Installation Guide for ccpm

The ccpm (Claude Code Project Manager) system now supports global installation, allowing you to run ccpm commands from any project directory without having to maintain separate `.claude` directories for each project.

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/automazeio/ccpm.git
cd ccpm

# Run the installation script
./install.sh

# Add to PATH (if not done automatically)
export PATH="$PATH:$HOME/.local/bin"
```

### Manual Installation

```bash
# Create installation directory
mkdir -p ~/.ccpm
cp -r .claude ~/.ccpm/
cp ccpm ~/.ccpm/
chmod +x ~/.ccpm/ccpm

# Create symlink
mkdir -p ~/.local/bin
ln -s ~/.ccpm/ccpm ~/.local/bin/ccpm

# Add to PATH in your shell config (.bashrc, .zshrc, etc.)
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
```

## Architecture

### Path Resolution

The system uses a smart path resolution mechanism (`path-resolver.sh`) that:

1. **Detects Installation Type**: Determines if running from global (`~/.ccpm`) or project-local installation
2. **Resolves Paths**: Automatically finds scripts, commands, and resources in the appropriate location
3. **Fallback Support**: Falls back to global installation when project-local resources aren't found

### Directory Structure

```
~/.ccpm/                    # Global installation
├── .claude/
│   ├── scripts/pm/        # PM scripts (globally available)
│   ├── commands/          # Command definitions
│   ├── agents/            # Agent definitions
│   └── VERSION            # System version
├── ccpm                   # Main executable
└── .claude-pm.yaml        # Global configuration

<project>/                  # Your project
├── .claude/               # Project-specific data only
│   ├── prds/             # Product requirement documents
│   ├── epics/            # Epic definitions
│   ├── context/          # Project context
│   └── .claude-pm.yaml   # Project configuration
└── CLAUDE.md              # Project-specific instructions
```

## Usage

### Global Commands

Once installed globally, use ccpm from any directory:

```bash
# Initialize a new project
cd /path/to/project
ccpm init

# Update the global installation
ccpm update

# Validate installation
ccpm validate

# Get help
ccpm help

# Run any PM command
ccpm status
ccpm standup
ccpm prd-new feature-name
```

### How It Works

1. **Script Location**: Scripts are stored in `~/.ccpm/.claude/scripts/`
2. **Project Data**: Project-specific data stays in `<project>/.claude/`
3. **Path Resolution**: The `path-resolver.sh` utility handles finding resources
4. **Environment Variables**:
   - `CCPM_HOME`: Points to installation directory
   - `CLAUDE_USE_GLOBAL`: Forces use of global resources

## Features

### Smart Path Resolution

The system automatically determines whether to use global or local resources:

- **Global Installation**: Scripts run from `~/.ccpm/.claude/scripts/`
- **Project Data**: PRDs, epics, and context stay in project's `.claude/`
- **Mixed Mode**: Can have both global scripts and project-local overrides

### Project Initialization

When you run `ccpm init` in a new project with global installation:

1. Creates minimal `.claude/` directory structure
2. Only creates directories for project data (prds, epics, context)
3. Uses global scripts - no copying needed
4. Creates project-specific `.claude-pm.yaml`

### Updates

Global installation makes updates easier:

```bash
# Update global installation
ccpm update

# All projects automatically use updated scripts
# Project data is preserved
```

## Environment Variables

- `CCPM_HOME`: Override installation directory (default: `~/.ccpm`)
- `CCPM_BIN_DIR`: Override bin directory (default: `~/.local/bin`)
- `CLAUDE_USE_GLOBAL`: Force global resource usage (set by ccpm wrapper)

## Troubleshooting

### Command Not Found

```bash
# Check if ccpm is in PATH
which ccpm

# If not found, add to PATH
export PATH="$PATH:$HOME/.local/bin"
```

### Permission Issues

```bash
# Make scripts executable
chmod +x ~/.ccpm/ccpm
chmod +x ~/.ccpm/.claude/scripts/pm/*.sh
```

### Path Resolution Issues

```bash
# Check installation type detection
source ~/.ccpm/.claude/scripts/pm/path-resolver.sh
echo $INSTALLATION_TYPE  # Should show "global"
```

## Benefits of Global Installation

1. **Single Source of Truth**: One set of scripts for all projects
2. **Easy Updates**: Update once, applies everywhere
3. **Reduced Disk Usage**: No duplicate scripts in every project
4. **Consistent Behavior**: Same version across all projects
5. **Clean Projects**: Projects only contain their data, not scripts

## Migration from Project-Local

If you have existing project-local installations:

```bash
# Back up project data
cp -r .claude/prds .claude/prds.backup
cp -r .claude/epics .claude/epics.backup

# Remove scripts (keep data)
rm -rf .claude/scripts
rm -rf .claude/commands
rm -rf .claude/agents

# Use global ccpm
ccpm validate
```

## Development

To develop or customize ccpm:

1. Fork the repository
2. Modify scripts in your fork
3. Install from your fork:
   ```bash
   git clone https://github.com/yourusername/ccpm.git
   cd ccpm
   ./install.sh
   ```

## Support

- Issues: https://github.com/automazeio/ccpm/issues
- Documentation: https://github.com/automazeio/ccpm

## License

See LICENSE file in the repository.