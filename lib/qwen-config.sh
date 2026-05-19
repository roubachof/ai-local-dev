#!/usr/bin/env bash
# ============================================================================
# Qwen/ai-local Configuration Library
# Shared variables and helpers for ai-local-dev scripts
# ============================================================================

AI_LOCAL_DEV_DIR="${AI_LOCAL_DEV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QWEN_LOCAL_CONF="${QWEN_LOCAL_CONF:-$AI_LOCAL_DEV_DIR/config/.qwen-local.conf}"
QWEN_LOCAL_CONF_LOCAL="${QWEN_LOCAL_CONF_LOCAL:-$QWEN_LOCAL_CONF.local}"
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.qwen/settings.json}"

# ---- Port defaults ----
LLAMA_PORT="${LLAMA_PORT:-8080}"
MLX_PORT="${MLX_PORT:-8082}"
LLAMA_PROXY_PORT="${LLAMA_PROXY_PORT:-8081}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_PROXY_PORT="${OLLAMA_PROXY_PORT:-11435}"
ROUTER_PORT="${ROUTER_PORT:-8090}"

# ---- Model defaults ----
QWEN_27B_MODEL="${QWEN_27B_MODEL:-$HOME/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf}"
QWEN_27B_MLX_MODEL="${QWEN_27B_MLX_MODEL:-mlx-community/Qwen3.6-27B-4bit}"
QWEN_35B_OLLAMA_MODEL="${QWEN_35B_OLLAMA_MODEL:-qwen3.6:35b-a3b}"
QWEN_8B_OLLAMA_MODEL="${QWEN_8B_OLLAMA_MODEL:-qwen3:8b}"
QWEN_SESSION_TOKEN_LIMIT="${QWEN_SESSION_TOKEN_LIMIT:-128000}"
BACKEND_27B="${BACKEND_27B:-llama}"

# ---- llama.cpp parameter defaults ----
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-131072}"
LLAMA_TEMP="${LLAMA_TEMP:-0.6}"
LLAMA_TOP_P="${LLAMA_TOP_P:-0.95}"
LLAMA_TOP_K="${LLAMA_TOP_K:-20}"
LLAMA_GPU_LAYERS="${LLAMA_GPU_LAYERS:-99}"
LLAMA_REASONING_FORMAT="${LLAMA_REASONING_FORMAT:-deepseek}"

# ---- MLX parameter defaults ----
MLX_TEMP="${MLX_TEMP:-0.6}"
MLX_TOP_P="${MLX_TOP_P:-0.95}"

# ---- Thinking control defaults ----
AI_LOCAL_FORCE_THINK="${AI_LOCAL_FORCE_THINK:-0}"
AI_LOCAL_NOTHINK_TEMP="${AI_LOCAL_NOTHINK_TEMP:-0.6}"
AI_LOCAL_NOTHINK_TOP_P="${AI_LOCAL_NOTHINK_TOP_P:-0.95}"
AI_LOCAL_THINK_TEMP="${AI_LOCAL_THINK_TEMP:-1.0}"
AI_LOCAL_THINK_TOP_P="${AI_LOCAL_THINK_TOP_P:-0.95}"
LLAMA_PROXY_FORCE_THINK="${LLAMA_PROXY_FORCE_THINK:-$AI_LOCAL_FORCE_THINK}"
OLLAMA_PROXY_FORCE_THINK="${OLLAMA_PROXY_FORCE_THINK:-$AI_LOCAL_FORCE_THINK}"
OLLAMA_PROXY_THINK="${OLLAMA_PROXY_THINK:-$AI_LOCAL_FORCE_THINK}"

# ---- Service timeouts ----
PROXY_TIMEOUT="${PROXY_TIMEOUT:-600}"
SERVICE_STARTUP_WAIT="${SERVICE_STARTUP_WAIT:-30}"

# ---- Runtime directories ----
AI_LOCAL_STATE_DIR="${AI_LOCAL_STATE_DIR:-$HOME/.local/state/ai-local}"
AI_LOCAL_LOG_DIR="${AI_LOCAL_LOG_DIR:-$AI_LOCAL_STATE_DIR/logs}"
AI_LOCAL_RUN_DIR="${AI_LOCAL_RUN_DIR:-$AI_LOCAL_STATE_DIR/run}"

load_qwen_config() {
    if [[ -f "$QWEN_LOCAL_CONF" ]]; then
        # shellcheck disable=SC1090
        source "$QWEN_LOCAL_CONF"
    fi
    if [[ -f "$QWEN_LOCAL_CONF_LOCAL" ]]; then
        # shellcheck disable=SC1090
        source "$QWEN_LOCAL_CONF_LOCAL"
    fi
}

ensure_state_dirs() {
    mkdir -p "$AI_LOCAL_LOG_DIR" "$AI_LOCAL_RUN_DIR"
}

service_url() {
    local port=$1
    local path="${2:-/health}"
    echo "http://127.0.0.1:${port}${path}"
}

is_service_running() {
    local port=$1
    local path="${2:-/health}"
    curl -sf "$(service_url "$port" "$path")" >/dev/null 2>&1
}

wait_for_service() {
    local port=$1
    local path="${2:-/health}"
    local max_wait="${3:-$SERVICE_STARTUP_WAIT}"
    local waited=0
    while [[ "$waited" -lt "$max_wait" ]]; do
        if is_service_running "$port" "$path"; then
            return 0
        fi
        waited=$((waited + 1))
        sleep 1
    done
    echo "⚠️  Service on port ${port}${path} did not become healthy within ${max_wait}s"
    return 1
}

show_config() {
    echo "=== ai-local Configuration ==="
    echo ""
    echo "QWEN_LOCAL_CONF=${QWEN_LOCAL_CONF}"
    echo "QWEN_LOCAL_CONF_LOCAL=${QWEN_LOCAL_CONF_LOCAL}"
    echo "LLAMA_PORT=${LLAMA_PORT}"
    echo "MLX_PORT=${MLX_PORT}"
    echo "LLAMA_PROXY_PORT=${LLAMA_PROXY_PORT}"
    echo "OLLAMA_PORT=${OLLAMA_PORT}"
    echo "OLLAMA_PROXY_PORT=${OLLAMA_PROXY_PORT}"
    echo "ROUTER_PORT=${ROUTER_PORT}"
    echo "QWEN_27B_MODEL=${QWEN_27B_MODEL}"
    echo "QWEN_27B_MLX_MODEL=${QWEN_27B_MLX_MODEL}"
    echo "QWEN_35B_OLLAMA_MODEL=${QWEN_35B_OLLAMA_MODEL}"
    echo "QWEN_8B_OLLAMA_MODEL=${QWEN_8B_OLLAMA_MODEL}"
    echo "QWEN_SESSION_TOKEN_LIMIT=${QWEN_SESSION_TOKEN_LIMIT}"
    echo "BACKEND_27B=${BACKEND_27B}"
    echo "LLAMA_CTX_SIZE=${LLAMA_CTX_SIZE}"
    echo "LLAMA_TEMP=${LLAMA_TEMP}"
    echo "LLAMA_TOP_P=${LLAMA_TOP_P}"
    echo "LLAMA_TOP_K=${LLAMA_TOP_K}"
    echo "LLAMA_GPU_LAYERS=${LLAMA_GPU_LAYERS}"
    echo "LLAMA_REASONING_FORMAT=${LLAMA_REASONING_FORMAT}"
    echo "MLX_TEMP=${MLX_TEMP}"
    echo "MLX_TOP_P=${MLX_TOP_P}"
    echo "AI_LOCAL_FORCE_THINK=${AI_LOCAL_FORCE_THINK}"
    echo "AI_LOCAL_NOTHINK_TEMP=${AI_LOCAL_NOTHINK_TEMP}"
    echo "AI_LOCAL_NOTHINK_TOP_P=${AI_LOCAL_NOTHINK_TOP_P}"
    echo "AI_LOCAL_THINK_TEMP=${AI_LOCAL_THINK_TEMP}"
    echo "AI_LOCAL_THINK_TOP_P=${AI_LOCAL_THINK_TOP_P}"
    echo "PROXY_TIMEOUT=${PROXY_TIMEOUT}"
    echo "SERVICE_STARTUP_WAIT=${SERVICE_STARTUP_WAIT}"
    echo "AI_LOCAL_LOG_DIR=${AI_LOCAL_LOG_DIR}"
    echo "AI_LOCAL_RUN_DIR=${AI_LOCAL_RUN_DIR}"
}

update_qwen_settings() {
    local base_url=$1
    local model_id=$2
    mkdir -p "$(dirname "$SETTINGS_FILE")"
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
    "sessionTokenLimit": ${QWEN_SESSION_TOKEN_LIMIT},
    "generationConfig": {
      "timeout": ${PROXY_TIMEOUT},
      "maxRetries": 1
    }
  },
  "\$version": 4
}
EOF
}
