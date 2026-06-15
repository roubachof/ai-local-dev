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

3. **llama.cpp** (for 27B)
   ```bash
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   make -j
   sudo cp llama-server /usr/local/bin/
   ```

4. **curl**
   ```bash
   brew install curl
   ```

## Install

```bash
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh
```

## Download models

```bash
ai-local download 27b      # llama.cpp GGUF
ai-local download 8b       # Ollama
ai-local download 35b      # Ollama
```

## Start services

```bash
ai-local 27b
ai-local 8b
ai-local 35b
ai-local status
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
ai-local config
```

## Local overrides

Keep custom settings in:

```bash
cp config/.qwen-local.conf config/.qwen-local.conf.local
```

Only `.qwen-local.conf.local` should be edited for machine-specific values.
