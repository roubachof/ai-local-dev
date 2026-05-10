# Architecture

## Overview

`ai-local-dev` provides local AI model inference through a proxy-based architecture that allows switching between models and controlling thinking behavior.

## High-Level Architecture

```
┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐
│  qwen-code  │───▶│  nothink proxy  │───▶│  AI Model Server │
│  (client)   │    │  (8081/11435)   │    │  (8080/11434)    │
└─────────────┘    └─────────────────┘    └──────────────────┘
                         │                         │
                    Disables thinking        Serves model
```

## Components

### 1. Model Servers

| Server | Port | Model | Framework |
|--------|------|-------|-----------|
| llama-server | 8080 | Qwen3.6-27B | llama.cpp |
| ollama | 11434 | Qwen3.6-35B-A3B | Ollama |

### 2. Proxies

#### `bin/ollama_nothink_proxy.py`
- **Purpose:** Disable thinking for Ollama/Qwen3.6-35B
- **Mechanism:** Injects `reasoning_effort:"none"` into request bodies
- **Port:** 11435 → 11434
- **Dependencies:** Python stdlib only (no external packages)
- **Control:** `OLLAMA_PROXY_FORCE_THINK=1` to enable thinking

#### `bin/llama_nonthink_proxy.py`
- **Purpose:** Strip reasoning content from llama-server/Qwen3.6-27B responses
- **Mechanism:** Converts `reasoning_content` → `content` in responses
- **Port:** 8081 → 8080
- **Dependencies:** fastapi, httpx, uvicorn
- **Control:** `LLAMA_PROXY_FORCE_THINK=1` to enable thinking

### 3. Orchestrator

#### `bin/ai-local`
- Unified CLI to start/stop models, launch agents, and manage proxies
- Sources configuration from `config/.qwen-local.conf`
- Updates `~/.qwen/settings.json` for qwen-code
- Commands: `ai-local {goose|qwen|27b|35b|status|stop|config|proxy}`

## Data Flow

### Request Flow (27B Model)
```
ai-local 27b → llama-server → llama_nonthink_proxy.py → qwen-code
                    ↓
            settings.json updated with:
            - model: Qwen3.6-27B-UD-Q4_K_XL.gguf
            - base_url: http://127.0.0.1:8081/v1
```

### Response Flow
```
llama-server → llama_nonthink_proxy.py → qwen-code
     ↓                    ↓
reasoning_content   reasoning_content stripped
in response         → content field
```

## Configuration

All settings centralized in `config/.qwen-local.conf`:

```bash
# Ports
LLAMA_PORT=8080
LLAMA_PROXY_PORT=8081
OLLAMA_PORT=11434
OLLAMA_PROXY_PORT=11435

# Model paths
QWEN_27B_MODEL="$HOME/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf"

# Performance
LLAMA_CTX_SIZE=131072
LLAMA_TEMP=0.6
LLAMA_TOP_P=0.95
LLAMA_TOP_K=20
LLAMA_GPU_LAYERS=99
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| OLLAMA_PROXY_FORCE_THINK | 0 | Enable thinking in Ollama proxy |
| LLAMA_PROXY_FORCE_THINK | 0 | Enable thinking in llama-server proxy |

## Security Considerations

- All services bind to `127.0.0.1` only (no external access)
- No authentication required for local proxies
- Model files stored in user's home directory
- Config file can be overridden per-user with `.qwen-local.conf.local`
