# Setup First Time Guide

## Prerequisites

Before installing `ai-local-dev`, install:

1. **Python 3.11+**
   ```bash
   # macOS
   brew install python
   ```

2. **Ollama** (required for 8B/35B)
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```

3. **Node.js 22+** (for qwen-code)
   ```bash
   nvm install 22
   ```

4. **curl**
   ```bash
   brew install curl
   ```

### Optional (fallback only)
`llama-server` is only needed when you set `BACKEND_27B=llama`.

```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
make -j
sudo cp llama-server /usr/local/bin/
```

## Install

```bash
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh
```

## Download models

Primary (MLX 27B + Ollama 8B/35B):

```bash
ai-local download 27b      # follows BACKEND_27B (default mlx)
ai-local download 8b
ai-local download 35b
```

Fallback llama.cpp GGUF:

```bash
ai-local download 27b-llama
```

## Start services

```bash
ai-local 27b        # uses BACKEND_27B from config
ai-local 8b
ai-local 35b
ai-local status
```

## Launch clients

```bash
ai-local goose
ai-local qwen
```

Thinking mode:

```bash
AI_LOCAL_FORCE_THINK=1 ai-local 27b
AI_LOCAL_FORCE_THINK=1 ai-local 8b
AI_LOCAL_FORCE_THINK=1 ai-local 35b
```

## Logs and diagnostics

```bash
ai-local logs 27b
ai-local logs 8b
ai-local logs 35b
ai-local doctor
bin/verify_nothink.sh
```

## Local overrides

Keep custom settings in:

```bash
cp config/.qwen-local.conf config/.qwen-local.conf.local
```

Only `.qwen-local.conf.local` should be edited for machine-specific values.
