#!/bin/bash
#
# dev.sh — Initialize Ollama environment + launch Goose
# Part of ai-local-dev: https://github.com/roubachof/ai-local-dev
#
# Usage:
#   ./bin/dev.sh goose         # Launch Goose with think OFF (via no-think proxy on :11435)
#   ./bin/dev.sh goose-think   # Launch Goose with think ON  (direct to Ollama :11434)
#   ./bin/dev.sh proxy-start   # Start the no-think proxy in the background
#   ./bin/dev.sh proxy-stop    # Stop the no-think proxy
#   ./bin/dev.sh proxy-status  # Show whether the proxy is listening on :11435
#   ./bin/dev.sh status        # Check Ollama, Goose, proxy status
#   ./bin/dev.sh env           # Show exported environment variables
#
# Environment:
#   AI_LOCAL_DEV_DIR    — Override path to ai-local-dev (default: script location)
#   OLLAMA_NOTHINK_PROXY_PORT — Proxy port (default: 11435)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_LOCAL_DEV_DIR="${AI_LOCAL_DEV_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Find Python venv: try AI_LOCAL_DEV_DIR first, then current directory, then system
if [ -f "$AI_LOCAL_DEV_DIR/.venv/bin/python" ]; then
    VENV_PYTHON="$AI_LOCAL_DEV_DIR/.venv/bin/python"
elif [ -f "$(pwd)/.venv/bin/python" ]; then
    VENV_PYTHON="$(pwd)/.venv/bin/python"
else
    VENV_PYTHON="python3"
fi

# No-think proxy (injects reasoning_effort:none into Goose -> Ollama traffic)
PROXY_PORT="${OLLAMA_NOTHINK_PROXY_PORT:-11435}"
PROXY_SCRIPT="$AI_LOCAL_DEV_DIR/bin/ollama_nothink_proxy.py"
PROXY_PID_FILE="/tmp/.ollama_nothink_proxy.pid"
PROXY_LOG_FILE="/tmp/.ollama_nothink_proxy.log"

# ============================================================================
# Environment
# ============================================================================

export VENV_PYTHON="$VENV_PYTHON"

# Ollama tuning for Qwen3.6:35b-a3b (MoE)
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_KEEP_ALIVE=30m
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
export OLLAMA_BASE_URL="http://localhost:11434"

export PYTHONDONTWRITEBYTECODE=1

# ============================================================================
# Helpers
# ============================================================================

log_info()    { echo "📌 $@"; }
log_warn()    { echo "⚠️  $@"; }
log_success() { echo "✅ $@"; }
log_error()   { echo "❌ $@"; exit 1; }

check_ollama() {
    command -v ollama &>/dev/null || { log_warn "Ollama not in PATH. Install: brew install ollama"; return 1; }
    curl -s http://localhost:11434/api/tags >/dev/null 2>&1 || { log_warn "Ollama daemon not running. Start with: ollama serve"; return 1; }
    ollama list | grep -q "qwen3.6:35b-a3b" || { log_warn "Model qwen3.6:35b-a3b missing. Pull with: ollama pull qwen3.6:35b-a3b"; return 1; }
    log_success "Ollama running, qwen3.6:35b-a3b available"
    return 0
}

check_goose() {
    command -v goose &>/dev/null || { log_warn "Goose not installed. Install with: brew install block-goose-cli"; return 1; }
    log_success "Goose $(goose --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo unknown) available"
    return 0
}


# ============================================================================
# Commands
# ============================================================================

show_status() {
    log_info "ai-local-dev status"
    echo "  Install dir: $AI_LOCAL_DEV_DIR"
    echo "  Python     : $VENV_PYTHON $([ -f "$VENV_PYTHON" ] && echo '(OK)' || echo '(using system)')"
    echo "  Proxy      : $PROXY_SCRIPT $([ -f "$PROXY_SCRIPT" ] && echo '(OK)' || echo '(MISSING)')"
    check_goose    || true
    check_ollama   || true
    proxy_status   || true
}

proxy_is_listening() {
    lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN >/dev/null 2>&1
}

start_proxy() {
    if proxy_is_listening; then
        log_success "No-think proxy already listening on :$PROXY_PORT"
        return 0
    fi
    [ -f "$PROXY_SCRIPT" ] || log_error "Proxy script missing: $PROXY_SCRIPT"
    [ -x "$VENV_PYTHON" ]  || log_error "venv Python missing: $VENV_PYTHON"
    nohup "$VENV_PYTHON" "$PROXY_SCRIPT" --port "$PROXY_PORT" \
        >"$PROXY_LOG_FILE" 2>&1 &
    echo $! >"$PROXY_PID_FILE"
    sleep 0.7
    if proxy_is_listening; then
        log_success "No-think proxy started on :$PROXY_PORT (PID $(cat "$PROXY_PID_FILE"))"
    else
        log_error "Proxy failed to bind. See $PROXY_LOG_FILE"
    fi
}

stop_proxy() {
    if [ -f "$PROXY_PID_FILE" ]; then
        pid=$(cat "$PROXY_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 0.3
            log_success "Stopped no-think proxy (PID $pid)"
        fi
        rm -f "$PROXY_PID_FILE"
    elif proxy_is_listening; then
        # No PID file but port is bound — kill by port owner.
        pid=$(lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)
        [ -n "$pid" ] && kill "$pid" && log_success "Stopped proxy listener (PID $pid)"
    else
        log_info "No proxy running on :$PROXY_PORT"
    fi
}

proxy_status() {
    if proxy_is_listening; then
        pid=$(lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)
        log_success "No-think proxy listening on :$PROXY_PORT (PID ${pid:-unknown})"
    else
        log_warn "No proxy on :$PROXY_PORT (think will be ON if Goose hits :11434 directly)"
    fi
}

launch_goose() {
    check_goose  || log_error "Install Goose first: brew install block-goose-cli"
    check_ollama || log_error "Start Ollama first: ollama serve"
    start_proxy

    log_info "Launching Goose session (think OFF, via no-think proxy)"
    echo "  Provider: ollama"
    echo "  Model   : qwen3.6:35b-a3b"
    echo "  Endpoint: http://localhost:$PROXY_PORT  (proxy -> :11434)"
    echo "  Context : 32K tokens"
    echo
    echo "  Tip: type /quit or Ctrl+D to exit"
    echo

    OLLAMA_HOST="http://localhost:$PROXY_PORT" goose session
}

launch_goose_think() {
    check_goose  || log_error "Install Goose first: brew install block-goose-cli"
    check_ollama || log_error "Start Ollama first: ollama serve"
    log_info "Launching Goose session (think ON, direct Ollama)"
    echo "  Provider: ollama"
    echo "  Model   : qwen3.6:35b-a3b"
    echo "  Endpoint: http://localhost:11434  (direct, thinking enabled)"
    echo
    echo "  Tip: type /quit or Ctrl+D to exit"
    echo

    OLLAMA_HOST="http://localhost:11434" goose session
}

show_env() {
    log_info "Exported environment"
    env | grep -E "^(OLLAMA|PYTHONPATH|VENV_PYTHON)=" | sort
}

# ============================================================================
# Main
# ============================================================================

COMMAND="${1:-status}"

case "$COMMAND" in
    goose)         launch_goose ;;
    goose-think)   launch_goose_think ;;
    proxy-start)   start_proxy ;;
    proxy-stop)    stop_proxy ;;
    proxy-status)  proxy_status ;;
    status)        show_status ;;
    env)           show_env ;;
    *)             log_error "Unknown command: $COMMAND. Usage: $0 {goose|goose-think|proxy-start|proxy-stop|proxy-status|status|env}" ;;
esac
