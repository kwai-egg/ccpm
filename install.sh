#!/bin/bash
# Installation script for ccpm (Claude Code Project Manager)
# This script sets up ccpm for global use

set -e

echo "Installing ccpm (Claude Code Project Manager)"
echo "=============================================="
echo ""

# Determine installation directory
INSTALL_DIR="${CCPM_INSTALL_DIR:-$HOME/.ccpm}"
BIN_DIR="${CCPM_BIN_DIR:-$HOME/.local/bin}"

# Create directories
echo "📁 Creating installation directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy files to installation directory
echo "📦 Installing ccpm to $INSTALL_DIR..."
if [[ -d "$SCRIPT_DIR/.claude" ]]; then
    cp -r "$SCRIPT_DIR/.claude" "$INSTALL_DIR/"
    echo "  ✅ Copied .claude directory"
fi

if [[ -f "$SCRIPT_DIR/ccpm" ]]; then
    cp "$SCRIPT_DIR/ccpm" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/ccpm"
    echo "  ✅ Copied ccpm executable"
fi

# Copy additional files
for file in README.md LICENSE AGENTS.md COMMANDS.md .claude-pm.yaml; do
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
        cp "$SCRIPT_DIR/$file" "$INSTALL_DIR/"
        echo "  ✅ Copied $file"
    fi
done

# Create symlink in bin directory
echo ""
echo "🔗 Creating command link..."
ln -sf "$INSTALL_DIR/ccpm" "$BIN_DIR/ccpm"
echo "  ✅ Created symlink: $BIN_DIR/ccpm"

# Set execute permissions on all scripts
echo ""
echo "🔧 Setting permissions..."
find "$INSTALL_DIR/.claude/scripts" -name "*.sh" -exec chmod +x {} \;
echo "  ✅ Scripts made executable"

# Check if bin directory is in PATH
echo ""
echo "🔍 Checking PATH configuration..."
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
    echo "  ✅ $BIN_DIR is in PATH"
else
    echo "  ⚠️  $BIN_DIR is not in PATH"
    echo ""
    echo "  Add to your shell configuration file (~/.bashrc, ~/.zshrc, etc.):"
    echo "    export PATH=\"\$PATH:$BIN_DIR\""
    echo ""
    
    # Try to detect shell and update config
    if [[ -n "$SHELL" ]]; then
        shell_name=$(basename "$SHELL")
        config_file=""
        
        case "$shell_name" in
            bash)
                config_file="$HOME/.bashrc"
                ;;
            zsh)
                config_file="$HOME/.zshrc"
                ;;
            fish)
                config_file="$HOME/.config/fish/config.fish"
                ;;
        esac
        
        if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
            read -p "  Would you like to add $BIN_DIR to PATH in $config_file? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "" >> "$config_file"
                echo "# Added by ccpm installer" >> "$config_file"
                echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$config_file"
                echo "  ✅ Added to $config_file"
                echo "  ⚠️  Please reload your shell or run: source $config_file"
            fi
        fi
    fi
fi

# Set environment variable
echo ""
echo "🌍 Setting environment..."
echo "  CCPM_HOME=$INSTALL_DIR"
export CCPM_HOME="$INSTALL_DIR"

# Create global Claude config if it doesn't exist
if [[ ! -d "$HOME/.claude" ]]; then
    echo ""
    echo "📝 Creating global Claude configuration..."
    mkdir -p "$HOME/.claude"
    ln -sf "$INSTALL_DIR/.claude/scripts" "$HOME/.claude/scripts"
    ln -sf "$INSTALL_DIR/.claude/commands" "$HOME/.claude/commands"
    ln -sf "$INSTALL_DIR/.claude/agents" "$HOME/.claude/agents"
    echo "  ✅ Global configuration created"
fi

# Summary
echo ""
echo "✅ Installation Complete!"
echo "========================"
echo ""
echo "📍 Installation location: $INSTALL_DIR"
echo "🔗 Command location: $BIN_DIR/ccpm"
echo ""
echo "🎯 Next steps:"
echo "  1. Reload your shell or run: source ~/.bashrc (or ~/.zshrc)"
echo "  2. Navigate to a project directory"
echo "  3. Run: ccpm init"
echo "  4. Run: ccpm help"
echo ""
echo "📚 Documentation: $INSTALL_DIR/README.md"
echo ""

# Test installation
if command -v ccpm >/dev/null 2>&1; then
    echo "✅ ccpm is available in current shell"
else
    echo "⚠️  ccpm not found in PATH - reload your shell first"
fi