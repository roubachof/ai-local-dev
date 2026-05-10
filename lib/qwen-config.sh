#!/usr/bin/env bash
# ============================================================================
# Qwen Configuration Library
# Shared functions and variables for ai-local-dev scripts
# ============================================================================

# ---- Default paths ----
AI_LOCAL_DEV_DIR="${AI_LOCAL_DEV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QWEN_LOCAL_CONF="${QWEN_LOCAL_CONF:-$AI_LOCAL_DEV_DIR/config/.qwen-local.conf}"
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.qwen/settings.json}"

# ---- Port defaults ----
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_PROXY_PORT="${LLAMA_PROXY_PORT:-8081}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_PROXY_PORT="${OLLAMA_PROXY_PORT:-11435}"

# ---- Model defaults ----
QWEN_27B_MODEL="${QWEN_27B_MODEL:-$HOME/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf}"

# ---- llama-server parameter defaults ----
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-131072}"
LLAMA_TEMP="${LLAMA_TEMP:-0.6}"
LLAMA_TOP_P="${LLAMA_TOP_P:-0.95}"
LLAMA_TOP_K="${LLAMA_TOP_K:-20}"
LLAMA_GPU_LAYERS="${LLAMA_GPU_LAYERS:-99}"

# ---- Service timeouts ----
PROXY_TIMEOUT="${PROXY_TIMEOUT:-600}"
SERVICE_STARTUP_WAIT="${SERVICE_STARTUP_WAIT:-10}"

# ============================================================================
# Functions
# ============================================================================

# Source user config if it exists
load_qwen_config() {
    if [[ -f "$QWEN_LOCAL_CONF" ]]; then
        source "$QWEN_LOCAL_CONF"
    fi
}

# Show all configuration values
show_config() {
    echo "=== Qwen Configuration ==="
    echo ""
    echo "Config file: ${QWEN_LOCAL_CONF}"
    if [[ -f "$QWEN_LOCAL_CONF" ]]; then
        echo "   ✅ Loaded"
    else
        echo "   ⚠️  Not found — using defaults"
    fi
    echo ""
    echo "LLAMA_PORT=${LLAMA_PORT}"
    echo "LLAMA_PROXY_PORT=${LLAMA_PROXY_PORT}"
    echo "OLLAMA_PORT=${OLLAMA_PORT}"
    echo "OLLAMA_PROXY_PORT=${OLLAMA_PROXY_PORT}"
    echo "QWEN_27B_MODEL=${QWEN_27B_MODEL}"
    echo "LLAMA_CTX_SIZE=${LLAMA_CTX_SIZE}"
    echo "LLAMA_TEMP=${LLAMA_TEMP}"
    echo "LLAMA_TOP_P=${LLAMA_TOP_P}"
    echo "LLAMA_TOP_K=${LLAMA_TOP_K}"
    echo "LLAMA_GPU_LAYERS=${LLAMA_GPU_LAYERS}"
    echo "PROXY_TIMEOUT=${PROXY_TIMEOUT}"
    echo "SERVICE_STARTUP_WAIT=${SERVICE_STARTUP_WAIT}"
}

# Check if a service is running on a given port
is_service_running() {
    local port=$1
    curl -sf http://127.0.0.1:${port}/health > /dev/null 2>&1
}

# Wait for a service to become healthy
wait_for_service() {
    local port=$1
    local wait=${SERVICE_STARTUP_WAIT}
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if is_service_running "$port"; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    
    echo "⚠️  Service on port ${port} did not become healthy within ${max_attempts}s"
    return 1
}

# Update qwen-code settings.json with model config
update_qwen_settings() {
    local model_id=$1
    local model_name=$2
    local base_url=$3
    
    cat > "$SETTINGS_FILE" << EOF
{
  "security": {
    "auth": {
      "selectedType": "openai",
      "apiKey": "sk-local-no-auth",
      "baseUrl": "${base_url}"
    }
  },
  "model": {
    "name": "${model_id}",
    "sessionTokenLimit": 32000,
    "generationConfig": {
      "timeout": ${PROXY_TIMEOUT},
      "maxRetries": 1
    }
  },
  "\$version": 4
}
EOF
    echo "✅ settings.json updated → model: ${model_name}"
}
