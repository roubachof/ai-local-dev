#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/qwen-config.sh"
load_qwen_config
ensure_state_dirs

PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="python3"
fi

TEMP_27B_FORCE_PORT="${TEMP_27B_FORCE_PORT:-8181}"
TEMP_35B_FORCE_PORT="${TEMP_35B_FORCE_PORT:-12435}"
PROMPT_TEXT="${PROMPT_TEXT:-What is 2+2? Reply with only the final number.}"
MODEL_27B_VERIFY="${MODEL_27B_VERIFY:-qwen3.6-27b}"
MODEL_35B_VERIFY="${MODEL_35B_VERIFY:-$QWEN_35B_OLLAMA_MODEL}"
AI_LOCAL_BIN="${AI_LOCAL_BIN:-$ROOT_DIR/bin/ai-local}"
STARTED_27B=0
STARTED_35B=0

UPSTREAM_27B=""
UPSTREAM_35B="http://127.0.0.1:${OLLAMA_PORT}"

TMP_PIDS=()
cleanup_temp_proxies() {
    for pid in "${TMP_PIDS[@]:-}"; do
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" 2>/dev/null || true
    done
    TMP_PIDS=()
}
cleanup() {
    cleanup_temp_proxies
    if [[ "$STARTED_27B" == "1" ]]; then
        "$AI_LOCAL_BIN" stop 27b >/dev/null 2>&1 || true
        STARTED_27B=0
    fi
    if [[ "$STARTED_35B" == "1" ]]; then
        "$AI_LOCAL_BIN" stop 35b >/dev/null 2>&1 || true
        STARTED_35B=0
    fi
}
trap cleanup EXIT

wait_http() {
    local port=$1
    local path="${2:-/health}"
    for _ in {1..30}; do
        if curl -sf "http://127.0.0.1:${port}${path}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

pick_27b_upstream() {
    local primary_port
    local primary_path
    local fallback_port
    local fallback_path
    if [[ "${BACKEND_27B:-mlx}" == "mlx" ]]; then
        primary_port="$MLX_PORT"
        primary_path="/v1/models"
        fallback_port="$LLAMA_PORT"
        fallback_path="/health"
    else
        primary_port="$LLAMA_PORT"
        primary_path="/health"
        fallback_port="$MLX_PORT"
        fallback_path="/v1/models"
    fi

    if wait_http "$primary_port" "$primary_path"; then
        echo "http://127.0.0.1:${primary_port}"
        return 0
    fi
    if wait_http "$fallback_port" "$fallback_path"; then
        echo "⚠️  verify_nothink: backend ${BACKEND_27B:-mlx} indisponible, fallback sur port ${fallback_port}" >&2
        echo "http://127.0.0.1:${fallback_port}"
        return 0
    fi

    echo "❌ Aucun backend 27B disponible (ports ${primary_port} / ${fallback_port})" >&2
    return 1
}

start_force_proxy() {
    local mode=$1
    local port=$2
    local upstream=$3
    local log_name=$4

    if wait_http "$port" "/health"; then
        return 0
    fi

    nohup env \
        AI_LOCAL_FORCE_THINK=1 \
        PROXY_TIMEOUT="$PROXY_TIMEOUT" \
        "$PYTHON_BIN" "$ROOT_DIR/bin/nothink_proxy.py" \
        --mode "$mode" \
        --port "$port" \
        --upstream-url "$upstream" \
        > "$AI_LOCAL_LOG_DIR/$log_name" 2>&1 &
    TMP_PIDS+=("$!")
    wait_http "$port" "/health" || {
        echo "❌ Failed to start temporary force-think proxy on port $port" >&2
        exit 1
    }
}

measure_endpoint() {
    local url=$1
    local model=$2
    "$PYTHON_BIN" - "$url" "$PROMPT_TEXT" "$model" <<'PY'
import json
import sys
import time
import urllib.request
import urllib.error

url = sys.argv[1]
prompt = sys.argv[2]
model = sys.argv[3]
payload = {
    "model": model,
    "stream": False,
    "messages": [{"role": "user", "content": prompt}],
}
req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)
start = time.perf_counter()
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = resp.read()
except urllib.error.HTTPError as exc:
    raise SystemExit(f"HTTP error {exc.code} on {url}: {exc.reason}") from exc
latency_ms = int((time.perf_counter() - start) * 1000)
data = json.loads(body.decode("utf-8"))
usage = data.get("usage", {}) if isinstance(data, dict) else {}
completion_tokens = usage.get("completion_tokens")
if completion_tokens is None:
    completion_tokens = -1
print(f"{latency_ms} {completion_tokens}")
PY
}

measure_with_retry() {
    local url=$1
    local model=$2
    local max_attempts="${3:-3}"
    local attempt=1
    local output=""

    while [[ "$attempt" -le "$max_attempts" ]]; do
        if output="$(measure_endpoint "$url" "$model" 2>/dev/null)"; then
            echo "$output"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    echo "❌ Measurement failed for ${url} after ${max_attempts} attempts" >&2
    return 1
}

resolve_model_id() {
    local base_url=$1
    local fallback=$2
    "$PYTHON_BIN" - "$base_url" "$fallback" <<'PY'
import json
import sys
import urllib.request

base_url = sys.argv[1]
fallback = sys.argv[2]
try:
    with urllib.request.urlopen(f"{base_url}/v1/models", timeout=15) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
except Exception:
    print(fallback)
    raise SystemExit(0)

data = payload.get("data")
if isinstance(data, list) and data:
    model_id = data[0].get("id")
    if model_id:
        print(model_id)
        raise SystemExit(0)
print(fallback)
PY
}

assert_ratios() {
    local label=$1
    local nt_latency=$2
    local nt_tokens=$3
    local ft_latency=$4
    local ft_tokens=$5

    local failed=0
    if [[ "$nt_tokens" -lt 0 || "$ft_tokens" -lt 0 ]]; then
        echo "❌ ${label}: missing completion token usage in responses"
        failed=1
    elif (( nt_tokens * 5 > ft_tokens )); then
        echo "❌ ${label}: completion token ratio too small (nothink=${nt_tokens}, force=${ft_tokens})"
        failed=1
    fi

    if (( nt_latency * 2 > ft_latency )); then
        echo "❌ ${label}: latency ratio too small (nothink=${nt_latency}ms, force=${ft_latency}ms)"
        failed=1
    fi

    return "$failed"
}

start_27b_phase() {
    local sample
    local model_27b
    if ! "$AI_LOCAL_BIN" 27b >/dev/null 2>&1; then
        echo "⚠️  verify_nothink: ai-local 27b a échoué, fallback sur 27b-llama" >&2
        "$AI_LOCAL_BIN" 27b-llama >/dev/null 2>&1
    fi
    STARTED_27B=1
    wait_http "$LLAMA_PROXY_PORT" "/health" || {
        echo "❌ 27B proxy is not healthy on port $LLAMA_PROXY_PORT" >&2
        return 1
    }
    model_27b="$(resolve_model_id "http://127.0.0.1:${LLAMA_PROXY_PORT}" "$MODEL_27B_VERIFY")"
    UPSTREAM_27B="$(pick_27b_upstream)"
    start_force_proxy "llama" "$TEMP_27B_FORCE_PORT" "$UPSTREAM_27B" "verify-force-27b.log"
    sample="$(measure_with_retry "http://127.0.0.1:${TEMP_27B_FORCE_PORT}/v1/chat/completions" "$model_27b")" || return 1
    read -r ft27_latency ft27_tokens <<< "$sample"
    sample="$(measure_with_retry "http://127.0.0.1:${LLAMA_PROXY_PORT}/v1/chat/completions" "$model_27b")" || return 1
    read -r nt27_latency nt27_tokens <<< "$sample"
    cleanup_temp_proxies
    "$AI_LOCAL_BIN" stop 27b >/dev/null 2>&1 || true
    STARTED_27B=0
}

start_35b_phase() {
    local sample
    local model_35b="$MODEL_35B_VERIFY"
    "$AI_LOCAL_BIN" 35b >/dev/null 2>&1
    STARTED_35B=1
    wait_http "$OLLAMA_PROXY_PORT" "/health" || {
        echo "❌ 35B proxy is not healthy on port $OLLAMA_PROXY_PORT" >&2
        return 1
    }
    start_force_proxy "ollama" "$TEMP_35B_FORCE_PORT" "$UPSTREAM_35B" "verify-force-35b.log"
    sample="$(measure_with_retry "http://127.0.0.1:${TEMP_35B_FORCE_PORT}/v1/chat/completions" "$model_35b")" || return 1
    read -r ft35_latency ft35_tokens <<< "$sample"
    sample="$(measure_with_retry "http://127.0.0.1:${OLLAMA_PROXY_PORT}/v1/chat/completions" "$model_35b")" || return 1
    read -r nt35_latency nt35_tokens <<< "$sample"
    cleanup_temp_proxies
    "$AI_LOCAL_BIN" stop 35b >/dev/null 2>&1 || true
    STARTED_35B=0
}

start_27b_phase
start_35b_phase

echo "=== verify_nothink.sh ==="
printf "%-12s %-14s %-18s %-14s %-18s\n" "proxy" "nothink_ms" "nothink_tokens" "force_ms" "force_tokens"
printf "%-12s %-14s %-18s %-14s %-18s\n" "27b" "$nt27_latency" "$nt27_tokens" "$ft27_latency" "$ft27_tokens"
printf "%-12s %-14s %-18s %-14s %-18s\n" "35b" "$nt35_latency" "$nt35_tokens" "$ft35_latency" "$ft35_tokens"

failures=0
assert_ratios "27b" "$nt27_latency" "$nt27_tokens" "$ft27_latency" "$ft27_tokens" || failures=$((failures + 1))
assert_ratios "35b" "$nt35_latency" "$nt35_tokens" "$ft35_latency" "$ft35_tokens" || failures=$((failures + 1))

if [[ "$failures" -gt 0 ]]; then
    exit 1
fi

echo "✅ nothink verification passed"
