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
    LLAMA_SPEC_TYPE LLAMA_SPEC_DRAFT_N_MAX LLAMA_SPEC_DRAFT_P_MIN
    LLAMA_SPEC_NGRAM_MOD_N_MATCH LLAMA_SPEC_NGRAM_MOD_N_MIN LLAMA_SPEC_NGRAM_MOD_N_MAX
    LLAMA_SPEC_NGRAM_SIMPLE_SIZE_N LLAMA_SPEC_NGRAM_SIMPLE_SIZE_M LLAMA_SPEC_NGRAM_SIMPLE_MIN_HITS
    LLAMA_SPEC_NGRAM_MAP_K_SIZE_N LLAMA_SPEC_NGRAM_MAP_K_SIZE_M LLAMA_SPEC_NGRAM_MAP_K_MIN_HITS
    LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_N LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_M LLAMA_SPEC_NGRAM_MAP_K4V_MIN_HITS
    AI_LOCAL_FORCE_THINK LLAMA_PROXY_FORCE_THINK
    AI_LOCAL_NOTHINK_TEMP AI_LOCAL_NOTHINK_TOP_P AI_LOCAL_THINK_TEMP AI_LOCAL_THINK_TOP_P
    AI_LOCAL_WARP_CTX_SOFT_LIMIT PROXY_TIMEOUT SERVICE_STARTUP_WAIT
    AI_LOCAL_SINGLE_MODEL_MODE AI_LOCAL_STATE_DIR AI_LOCAL_LOG_DIR AI_LOCAL_RUN_DIR
)

# Capture which config vars are inherited from the environment BEFORE the
# built-in ${VAR:-default} assignments below run. load_qwen_config restores only
# these, so ad-hoc env overrides (e.g. `LLAMA_MTP=1 ai-local 35b`) win over the
# conf file, while built-in defaults do NOT clobber conf-file values. Without
# this, every ${VAR:-default} would mark the var as "set" and the snapshot/restore
# in load_qwen_config would silently override the conf file with the defaults
# (env > conf > default would instead behave as (env|default) > conf).
AI_LOCAL_ENV_INHERITED=()
for _v in "${AI_LOCAL_CONFIG_VARS[@]}"; do
    if [[ -n "${!_v+set}" ]]; then
        AI_LOCAL_ENV_INHERITED+=("$_v")
        printf -v "_ai_local_env_val_$_v" '%s' "${!_v}"
    fi
done
unset _v

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
# Speculative-decoding flavor. LLAMA_MTP remains the on/off gate; LLAMA_SPEC_TYPE
# selects the backend(s) (comma-separated, llama.cpp build 9750): draft-mtp
# (default), ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod, ngram-cache.
# Combine e.g. "draft-mtp,ngram-mod,ngram-map-k4v". n-gram sub-flags below are
# emitted only when their mode is in LLAMA_SPEC_TYPE; defaults match llama.cpp's
# own defaults so they don't pre-bias Apple Silicon results. For ngram-only runs
# you may set LLAMA_SPEC_DRAFT_N_MAX, but ngram modes also use their own n-*
# range (see bench/README.md "n-gram spec-decode axis").
LLAMA_SPEC_TYPE="${LLAMA_SPEC_TYPE:-draft-mtp}"
LLAMA_SPEC_DRAFT_N_MAX="${LLAMA_SPEC_DRAFT_N_MAX:-}"
LLAMA_SPEC_DRAFT_P_MIN="${LLAMA_SPEC_DRAFT_P_MIN:-}"
LLAMA_SPEC_NGRAM_MOD_N_MATCH="${LLAMA_SPEC_NGRAM_MOD_N_MATCH:-24}"
LLAMA_SPEC_NGRAM_MOD_N_MIN="${LLAMA_SPEC_NGRAM_MOD_N_MIN:-48}"
LLAMA_SPEC_NGRAM_MOD_N_MAX="${LLAMA_SPEC_NGRAM_MOD_N_MAX:-64}"
LLAMA_SPEC_NGRAM_SIMPLE_SIZE_N="${LLAMA_SPEC_NGRAM_SIMPLE_SIZE_N:-12}"
LLAMA_SPEC_NGRAM_SIMPLE_SIZE_M="${LLAMA_SPEC_NGRAM_SIMPLE_SIZE_M:-48}"
LLAMA_SPEC_NGRAM_SIMPLE_MIN_HITS="${LLAMA_SPEC_NGRAM_SIMPLE_MIN_HITS:-1}"
LLAMA_SPEC_NGRAM_MAP_K_SIZE_N="${LLAMA_SPEC_NGRAM_MAP_K_SIZE_N:-12}"
LLAMA_SPEC_NGRAM_MAP_K_SIZE_M="${LLAMA_SPEC_NGRAM_MAP_K_SIZE_M:-48}"
LLAMA_SPEC_NGRAM_MAP_K_MIN_HITS="${LLAMA_SPEC_NGRAM_MAP_K_MIN_HITS:-1}"
LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_N="${LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_N:-12}"
LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_M="${LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_M:-48}"
LLAMA_SPEC_NGRAM_MAP_K4V_MIN_HITS="${LLAMA_SPEC_NGRAM_MAP_K4V_MIN_HITS:-1}"

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
    # Capture only vars that were INHERITED from the environment. The set of
    # env-inherited vars (and their original values) was captured at source time
    # in AI_LOCAL_ENV_INHERITED / _ai_local_env_val_<name>, BEFORE the built-in
    # ${VAR:-default} assignments ran. Restoring only those gives precedence
    # env > conf > built-in default; otherwise every default would masquerade as
    # an env override and silently clobber conf-file values.
    local _is_env _e
    for _saved_name in "${_var_names[@]}"; do
        _is_env=0
        for _e in "${AI_LOCAL_ENV_INHERITED[@]:-}"; do
            [[ -z "$_e" ]] && continue
            [[ "$_e" == "$_saved_name" ]] && { _is_env=1; break; }
        done
        if [[ "$_is_env" == "1" ]]; then
            _env_names+=("$_saved_name")
            # Copy the original env value (captured before defaults) for restore.
            local _src="_ai_local_env_val_$_saved_name"
            printf -v "_env_val_$_saved_name" '%s' "${!_src}"
        fi
    done
    unset _is_env _e

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
        local _src="_env_val_$_saved_name"
        printf -v "$_saved_name" '%s' "${!_src}"
        unset "$_src"
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
    echo "LLAMA_SPEC_TYPE=${LLAMA_SPEC_TYPE}"
    echo "LLAMA_SPEC_DRAFT_N_MAX=${LLAMA_SPEC_DRAFT_N_MAX:-<auto>}"
    echo "LLAMA_SPEC_DRAFT_P_MIN=${LLAMA_SPEC_DRAFT_P_MIN:-<default>}"
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
