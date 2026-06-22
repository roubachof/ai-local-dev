#!/usr/bin/env bash
# ============================================================================
# ai-local-dev Installer
# Sets up local AI infrastructure on a new machine
# Usage: ./install.sh [--dry-run]
#
# This installer creates SYMLINKS from ~/.local/bin/ to this repo directory.
# No files are copied — all updates happen via `git pull` in the repo.
# ============================================================================
set -euo pipefail

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---- Configuration ----
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
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
log_info()    { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }

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

symlink_file() {
    local src="$1"
    local name="$2"
    local dst="$BIN_DIR/$name"
    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would symlink: $src -> $dst"
        return
    fi
    # Remove existing file/symlink
    if [ -L "$dst" ] || [ -f "$dst" ]; then
        rm -f "$dst"
    fi
    ln -s "$src" "$dst"
    log_info "Symlinked: $name -> $src"
}

# ---- Main Installation ----
echo "=== ai-local-dev Installer ==="
echo "  Repo: $REPO_DIR"
echo ""

# 1. Check prerequisites
echo "🔍 Checking prerequisites..."
echo ""

MISSING=0
check_prerequisite "python3" "Python 3" || MISSING=$((MISSING+1))
check_prerequisite "curl" "curl" || MISSING=$((MISSING+1))
check_prerequisite "node" "Node.js" || MISSING=$((MISSING+1))
check_prerequisite "llama-server" "llama-server (llama.cpp)" || MISSING=$((MISSING+1))
# Ollama is now optional (only needed for the legacy `ai-local 35b-ollama` backend).
check_prerequisite "ollama" "Ollama (optional)" || true

# mlx-lm is optional (enables the MLX backend via `ai-local *-mlx`).
# It is Apple-Silicon-only and pulled in via requirements.txt on arm64 macOS.
if [[ "$(uname)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    if "$REPO_DIR/.venv/bin/python" -c "import mlx_lm.server" >/dev/null 2>&1 2>/dev/null || command -v mlx_lm.server >/dev/null 2>&1; then
        log_info "mlx-lm is installed (MLX backend ready)"
    else
        log_warn "mlx-lm is NOT installed (optional; for MLX backend: pip install 'mlx-lm>=0.31')"
    fi
else
    log_warn "mlx-lm skipped (Apple Silicon only; not available on $(uname -m))"
fi

echo ""
if [ $MISSING -gt 0 ]; then
    log_warn "$MISSING prerequisite(s) missing. Install them before using ai-local-dev."
    echo "   See: docs/SETUP_FIRST_TIME.md  (llama.cpp now drives both 27B and 35B)"
    echo ""
fi

# 2. Setup Python environment
echo "🐍 Setting up Python environment..."
VENV_DIR="$REPO_DIR/.venv"
if [ "$DRY_RUN" = false ]; then
    if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python" ]; then
        log_info "venv already exists: $VENV_DIR"
    else
        python3 -m venv "$VENV_DIR"
        log_info "Created venv: $VENV_DIR"
    fi
    "$VENV_DIR/bin/pip" install -q -r "$REPO_DIR/requirements.txt"
    log_info "Installed Python dependencies (fastapi, httpx, uvicorn; mlx-lm on Apple Silicon)"
else
    echo "   [DRY RUN] Would set up venv and install dependencies"
fi
echo ""

# 3. Ensure bin directory exists
echo "📁 Setting up bin directory..."
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$BIN_DIR"
fi
log_info "Bin dir: $BIN_DIR"
echo ""

# 4. Create symlinks for all executable files
echo "🔗 Creating symlinks..."
symlink_file "$REPO_DIR/bin/ai-local"                   "ai-local"
symlink_file "$REPO_DIR/bin/nothink_proxy.py"            "nothink_proxy.py"
symlink_file "$REPO_DIR/bin/model_router.py"             "model_router.py"
echo ""

# 5. Setup shell aliases
echo "🔧 Setting up shell aliases..."
ALIAS_FILE="$HOME/.zshrc"
if [ "$DRY_RUN" = false ]; then
    if ! grep -q "# ai-local-dev aliases" "$ALIAS_FILE" 2>/dev/null; then
        {
            echo ""
            echo "# ai-local-dev aliases"
            echo "alias ai27b='ai-local 27b'"
            echo "alias ai35b='ai-local 35b'"
            echo "alias ai-status='ai-local status'"
            echo "alias ai-stop='ai-local stop'"
        } >> "$ALIAS_FILE"
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
    if command -v ai-local &> /dev/null; then
        log_info "ai-local is available in PATH"
        echo ""
        echo "📋 Current status:"
        ai-local status
    else
        log_error "ai-local not found in PATH"
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
echo "   2. Download models: ai-local download 27b-mtp  &&  ai-local download 35b"
echo "   3. Check status:      ai-local status"
echo "   4. Start a model:     ai-local 27b  (or ai-local 35b)"
echo ""
echo "💡 Tip: To update, just run 'git pull' in $REPO_DIR"
echo "   No reinstallation needed — symlinks point to the repo directly."
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 This was a dry run. No changes were made.${NC}"
fi
