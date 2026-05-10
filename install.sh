#!/usr/bin/env bash
# ============================================================================
# ai-local-dev Installer
# Sets up local AI infrastructure on a new machine
# Usage: ./install.sh [--dry-run]
# ============================================================================
set -euo pipefail

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---- Configuration ----
INSTALL_DIR="${HOME}/.local/share/ai-local-dev"
BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# ---- Parse arguments ----
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            echo -e "${YELLOW}🔍 Dry run mode - no changes will be made${NC}"
            ;;
    esac
done

# ---- Helper functions ----
log_info() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

check_prerequisite() {
    local cmd=$1
    local name=$2
    if command -v "$cmd" &> /dev/null; then
        log_info "$name is installed: $(command -v $cmd)"
        return 0
    else
        log_warn "$name is NOT installed"
        return 1
    fi
}

copy_file() {
    local src=$1
    local dst=$2
    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would copy: $src -> $dst"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod +x "$dst"
    log_info "Copied: $src -> $dst"
}

# ---- Main Installation ----
echo "=== ai-local-dev Installer ==="
echo ""

# 1. Check prerequisites
echo "🔍 Checking prerequisites..."
echo ""

MISSING=0
check_prerequisite "python3" "Python 3" || MISSING=$((MISSING+1))
check_prerequisite "ollama" "Ollama" || MISSING=$((MISSING+1))
check_prerequisite "llama-server" "llama-server (llama.cpp)" || MISSING=$((MISSING+1))
check_prerequisite "curl" "curl" || MISSING=$((MISSING+1))
check_prerequisite "node" "Node.js" || MISSING=$((MISSING+1))

echo ""
if [ $MISSING -gt 0 ]; then
    log_warn "$MISSING prerequisite(s) missing. Install them before using ai-local-dev."
    echo "   See: docs/SETUP_FIRST_TIME.md"
    echo ""
fi

# 2. Create installation directory
echo "📁 Setting up installation directory..."
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
fi
log_info "Install dir: $INSTALL_DIR"
log_info "Bin dir: $BIN_DIR"
echo ""

# 3. Copy project files
echo "📦 Copying project files..."
copy_file "$SCRIPT_DIR/bin/qwen-switch" "$INSTALL_DIR/bin/qwen-switch"
copy_file "$SCRIPT_DIR/bin/ollama_nothink_proxy.py" "$INSTALL_DIR/bin/"
copy_file "$SCRIPT_DIR/bin/llama_nonthink_proxy.py" "$INSTALL_DIR/bin/"
copy_file "$SCRIPT_DIR/lib/qwen-config.sh" "$INSTALL_DIR/lib/"
copy_file "$SCRIPT_DIR/config/.qwen-local.conf" "$INSTALL_DIR/config/"
echo ""

# 4. Create symlinks in PATH
echo "🔗 Creating symlinks..."
if [ "$DRY_RUN" = false ]; then
    ln -sf "$INSTALL_DIR/bin/qwen-switch" "$BIN_DIR/qwen-switch"
    log_info "Symlinked: qwen-switch -> $BIN_DIR/qwen-switch"
fi
echo ""

# 5. Setup shell aliases
echo "🔧 Setting up shell aliases..."
ALIAS_FILE="$HOME/.zshrc"
if [ "$DRY_RUN" = false ]; then
    # Add aliases if they don't already exist
    if ! grep -q "q22=" "$ALIAS_FILE" 2>/dev/null; then
        echo "" >> "$ALIAS_FILE"
        echo "# ai-local-dev aliases" >> "$ALIAS_FILE"
        echo "alias q22='node --version >/dev/null 2>&1 && q22'" >> "$ALIAS_FILE"
        echo "alias qwen-27b='qwen-switch 27b'" >> "$ALIAS_FILE"
        echo "alias qwen-35b='qwen-switch 35b'" >> "$ALIAS_FILE"
        echo "alias qwen-status='qwen-switch status'" >> "$ALIAS_FILE"
        echo "alias qwen-stop='qwen-switch stop'" >> "$ALIAS_FILE"
        log_info "Added aliases to $ALIAS_FILE"
    else
        log_info "Aliases already exist in $ALIAS_FILE"
    fi
else
    echo "   [DRY RUN] Would add aliases to $ALIAS_FILE"
fi
echo ""

# 6. Verify installation
echo "🧪 Verifying installation..."
if [ "$DRY_RUN" = false ]; then
    if command -v qwen-switch &> /dev/null; then
        log_info "qwen-switch is available in PATH"
        echo ""
        echo "📋 Current status:"
        qwen-switch status
    else
        log_error "qwen-switch not found in PATH"
        echo "   Make sure $BIN_DIR is in your PATH"
        echo "   Add to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
        exit 1
    fi
else
    echo "   [DRY RUN] Would verify installation"
fi
echo ""

# 7. Next steps
echo "🎉 Installation complete!"
echo ""
echo "Next steps:"
echo "   1. Source your shell config: source $ALIAS_FILE"
echo "   2. Check status: qwen-switch status"
echo "   3. Start a model: qwen-switch 27b"
echo "   4. Launch qwen-code: q22"
echo ""
echo "📖 Documentation: $INSTALL_DIR/docs/"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 This was a dry run. No changes were made.${NC}"
fi
