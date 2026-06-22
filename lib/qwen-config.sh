#!/usr/bin/env bash
# ============================================================================
# Qwen/ai-local Configuration Library
# Shared variables and helpers for ai-local-dev scripts
# ============================================================================

AI_LOCAL_DEV_DIR="${AI_LOCAL_DEV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QWEN_LOCAL_CONF="${QWEN_LOCAL_CONF:-$AI_LOCAL_DEV_DIR/config/.qwen-local.conf}"
QWEN_LOCAL_CONF_LOCAL="${QWEN_LOCAL_CONF_LOCAL:-$QWEN_LOCAL_CONF.local}"
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.qwen/settings.json}"

# Config var names that load_qwen_config snapshots before sourcing the conf
# files so ad-hoc env overrides (e.g. `LLAMA_MTP=1 ai-local 35b`) survive. Keep
# this in sync with the vars defined below.
AI_LOCAL_CONFIG_VARS=(
    LLAMA_PORT LLAMA_35B_PORT LLAMA_PROXY_PORT PROXY_35B_PORT ROUTER_PORT
    QWEN_27B_MODEL QWEN_27B_MTP_MODEL QWEN_35B_MODEL QWEN_35B_MTP_MODEL QWEN_SESSION_TOKEN_LIMIT
    LLAMA_CTX_SIZE LLAMA_35B_CTX_SIZE LLAMA_TEMP LLAMA_TOP_P LLAMA_TOP_K LLAMA_GPU_LAYERS
    LLAMA_REASONING_FORMAT LLAMA_CACHE_TYPE_K LLAMA_CACHE_TYPE_V
    LLAMA_CTX_CHECKPOINTS LLAMA_CHECKPOINT_EVERY_N_TOKENS LLAMA_SWA_FULL
    LLAMA_MTP LLAMA_MTP_N_MAX_27B LLAMA_MTP_N_MAX_35B LLAMA_PRESERVE_THINKING
    AI_LOCAL_FORCE_THINK LLAMA_PROXY_FORCE_THINK
    AI_LOCAL_NOTHINK_TEMP AI_LOCAL_NOTHINK_TOP_P AI_LOCAL_THINK_TEMP AI_LOCAL_THINK_TOP_P
    AI_LOCAL_WARP_CTX_SOFT_LIMIT PROXY_TIMEOUT SERVICE_STARTUP_WAIT
    AI_LOCAL_SINGLE_MODEL_MODE AI_LOCAL_STATE_DIR AI_LOCAL_LOG_DIR AI_LOCAL_RUN_DIR
)

# ---- Port defaults ----
LLAMA_PORT="${LLAMA_PORT:-8080}"              # 27B llama-server
LLAMA_35B_PORT="${LLAMA_35B_PORT:-8083}"       # 35B llama-server
LLAMA_PROXY_PORT="${LLAMA_PROXY_PORT:-8081}"   # 27B no-think proxy
PROXY_35B_PORT="${PROXY_35B_PORT:-11435}"      # 35B no-think proxy
ROUTER_PORT="${ROUTER_PORT:-8090}"

# ---- Model defaults ----
QWEN_27B_MODEL="${QWEN_27B_MODEL:-$HOME/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf}"
QWEN_27B_MTP_MODEL="${QWEN_27B_MTP_MODEL:-$HOME/.local/share/llama-models/mtp/Qwen3.6-27B-UD-Q4_K_XL.gguf}"
QWEN_35B_MODEL="${QWEN_35B_MODEL:-$HOME/.local/share/llama-models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
QWEN_35B_MTP_MODEL="${QWEN_35B_MTP_MODEL:-$HOME/.local/share/llama-models/mtp/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
QWEN_SESSION_TOKEN_LIMIT="${QWEN_SESSION_TOKEN_LIMIT:-32000}"

# ---- llama.cpp parameter defaults (shared by 27B and 35B unless overridden) ----
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-65536}"
LLAMA_35B_CTX_SIZE="${LLAMA_35B_CTX_SIZE:-131072}"
LLAMA_TEMP="${LLAMA_TEMP:-0.6}"
LLAMA_TOP_P="${LLAMA_TOP_P:-0.95}"
LLAMA_TOP_K="${LLAMA_TOP_K:-20}"
LLAMA_GPU_LAYERS="${LLAMA_GPU_LAYERS:-99}"
LLAMA_REASONING_FORMAT="${LLAMA_REASONING_FORMAT:-deepseek}"
LLAMA_CACHE_TYPE_K="${LLAMA_CACHE_TYPE_K:-q8_0}"
LLAMA_CACHE_TYPE_V="${LLAMA_CACHE_TYPE_V:-q8_0}"
# Hybrid Gated-DeltaNet cache + MTP flags (multi-turn agentic perf fix).
LLAMA_CTX_CHECKPOINTS="${LLAMA_CTX_CHECKPOINTS:-128}"
LLAMA_CHECKPOINT_EVERY_N_TOKENS="${LLAMA_CHECKPOINT_EVERY_N_TOKENS:-4096}"
LLAMA_SWA_FULL="${LLAMA_SWA_FULL:-1}"
# On by default: MTP speculative decoding gives a real decode speedup on
# Apple Silicon/Metal (measured +42% on the 27B dense, +23% on the 35B-A3B MoE;
# see bench/README.md). Disable with LLAMA_MTP=0 to drop --spec-type and skip the
# MTP draft context (saves a little RAM).
LLAMA_MTP="${LLAMA_MTP:-1}"
LLAMA_MTP_N_MAX_27B="${LLAMA_MTP_N_MAX_27B:-3}"
LLAMA_MTP_N_MAX_35B="${LLAMA_MTP_N_MAX_35B:-2}"
LLAMA_PRESERVE_THINKING="${LLAMA_PRESERVE_THINKING:-1}"

# ---- Thinking control defaults ----
AI_LOCAL_FORCE_THINK="${AI_LOCAL_FORCE_THINK:-0}"
AI_LOCAL_NOTHINK_TEMP="${AI_LOCAL_NOTHINK_TEMP:-0.6}"
AI_LOCAL_NOTHINK_TOP_P="${AI_LOCAL_NOTHINK_TOP_P:-0.95}"
AI_LOCAL_THINK_TEMP="${AI_LOCAL_THINK_TEMP:-1.0}"
AI_LOCAL_THINK_TOP_P="${AI_LOCAL_THINK_TOP_P:-0.95}"
AI_LOCAL_WARP_CTX_SOFT_LIMIT="${AI_LOCAL_WARP_CTX_SOFT_LIMIT:-28000}"
# Legacy alias still honored alongside the canonical AI_LOCAL_FORCE_THINK.
LLAMA_PROXY_FORCE_THINK="${LLAMA_PROXY_FORCE_THINK:-$AI_LOCAL_FORCE_THINK}"

# ---- Service timeouts ----
PROXY_TIMEOUT="${PROXY_TIMEOUT:-600}"
SERVICE_STARTUP_WAIT="${SERVICE_STARTUP_WAIT:-30}"

# ---- Runtime behavior ----
AI_LOCAL_SINGLE_MODEL_MODE="${AI_LOCAL_SINGLE_MODEL_MODE:-1}"

# ---- Runtime directories ----
AI_LOCAL_STATE_DIR="${AI_LOCAL_STATE_DIR:-$HOME/.local/state/ai-local}"
AI_LOCAL_LOG_DIR="${AI_LOCAL_LOG_DIR:-$AI_LOCAL_STATE_DIR/logs}"
AI_LOCAL_RUN_DIR="${AI_LOCAL_RUN_DIR:-$AI_LOCAL_STATE_DIR/run}"

load_qwen_config() {
    # Config files use direct assignment (VAR=value), which would clobber any
    # ad-hoc env override like `LLAMA_MTP=1 ai-local 35b`. Snapshot the config
    # vars that are already set in the environment BEFORE sourcing the conf
    # files, then restore them afterward so env overrides take precedence.
    #
    # Snapshots use indirection (${!var}) + eval for restore, so this works on
    # bash 3.2 (macOS default) with no associative arrays or namerefs. Defaults
    # to $AI_LOCAL_CONFIG_VARS unless callers pass an explicit var list.
    local -a _var_names=("${@:-${AI_LOCAL_CONFIG_VARS[@]}}")
    local -a _env_names=()
    local _saved_name _saved_val
    for _saved_name in "${_var_names[@]}"; do
        # Capture only if the var is present in the environment (inherited/exported).
        if [[ -n "${!_saved_name+set}" ]]; then
            _saved_val="${!_saved_name}"
            _env_names+=("$_saved_name")
            # Stash the value in a uniquely-named var for restore. Use printf %q
            # to safely quote the value so eval restores it verbatim.
            printf -v "_env_val_$_saved_name" '%s' "$_saved_val"
        fi
    done

    if [[ -f "$QWEN_LOCAL_CONF" ]]; then
        # shellcheck disable=SC1090
        source "$QWEN_LOCAL_CONF"
    fi
    if [[ -f "$QWEN_LOCAL_CONF_LOCAL" ]]; then
        # shellcheck disable=SC1090
        source "$QWEN_LOCAL_CONF_LOCAL"
    fi

    # Re-apply env-inherited values so they win over conf defaults.
    for _saved_name in "${_env_names[@]:-}"; do
        [[ -n "$_saved_name" ]] || continue
        eval "$_saved_name=\"\${_env_val_$_saved_name}\""
        unset "_env_val_$_saved_name"
    done
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
    echo "LLAMA_35B_PORT=${LLAMA_35B_PORT}"
    echo "LLAMA_PROXY_PORT=${LLAMA_PROXY_PORT}"
    echo "PROXY_35B_PORT=${PROXY_35B_PORT}"
    echo "ROUTER_PORT=${ROUTER_PORT}"
    echo "QWEN_27B_MODEL=${QWEN_27B_MODEL}"
    echo "QWEN_27B_MTP_MODEL=${QWEN_27B_MTP_MODEL}"
    echo "QWEN_35B_MODEL=${QWEN_35B_MODEL}"
    echo "QWEN_35B_MTP_MODEL=${QWEN_35B_MTP_MODEL}"
    echo "QWEN_SESSION_TOKEN_LIMIT=${QWEN_SESSION_TOKEN_LIMIT}"
    echo "LLAMA_CTX_SIZE=${LLAMA_CTX_SIZE}"
    echo "LLAMA_35B_CTX_SIZE=${LLAMA_35B_CTX_SIZE}"
    echo "LLAMA_TEMP=${LLAMA_TEMP}"
    echo "LLAMA_TOP_P=${LLAMA_TOP_P}"
    echo "LLAMA_TOP_K=${LLAMA_TOP_K}"
    echo "LLAMA_GPU_LAYERS=${LLAMA_GPU_LAYERS}"
    echo "LLAMA_REASONING_FORMAT=${LLAMA_REASONING_FORMAT}"
    echo "LLAMA_CACHE_TYPE_K=${LLAMA_CACHE_TYPE_K}"
    echo "LLAMA_CACHE_TYPE_V=${LLAMA_CACHE_TYPE_V}"
    echo "LLAMA_CTX_CHECKPOINTS=${LLAMA_CTX_CHECKPOINTS}"
    echo "LLAMA_CHECKPOINT_EVERY_N_TOKENS=${LLAMA_CHECKPOINT_EVERY_N_TOKENS}"
    echo "LLAMA_SWA_FULL=${LLAMA_SWA_FULL}"
    echo "LLAMA_MTP=${LLAMA_MTP}"
    echo "LLAMA_MTP_N_MAX_27B=${LLAMA_MTP_N_MAX_27B}"
    echo "LLAMA_MTP_N_MAX_35B=${LLAMA_MTP_N_MAX_35B}"
    echo "LLAMA_PRESERVE_THINKING=${LLAMA_PRESERVE_THINKING}"
    echo "AI_LOCAL_SINGLE_MODEL_MODE=${AI_LOCAL_SINGLE_MODEL_MODE}"
    echo "AI_LOCAL_FORCE_THINK=${AI_LOCAL_FORCE_THINK}"
    echo "AI_LOCAL_NOTHINK_TEMP=${AI_LOCAL_NOTHINK_TEMP}"
    echo "AI_LOCAL_NOTHINK_TOP_P=${AI_LOCAL_NOTHINK_TOP_P}"
    echo "AI_LOCAL_THINK_TEMP=${AI_LOCAL_THINK_TEMP}"
    echo "AI_LOCAL_THINK_TOP_P=${AI_LOCAL_THINK_TOP_P}"
    echo "AI_LOCAL_WARP_CTX_SOFT_LIMIT=${AI_LOCAL_WARP_CTX_SOFT_LIMIT}"
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
