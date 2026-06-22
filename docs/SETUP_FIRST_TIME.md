# Setup First Time Guide

## Prerequisites

Before installing `ai-local-dev`, install:

1. **Python 3.11+**
   ```bash
   # macOS
   brew install python
   ```

2. **llama.cpp** (required — drives both 27B and 35B)
   ```bash
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   make -j
   sudo cp llama-server /usr/local/bin/
   ```
   Verify the build exposes the hybrid-cache + MTP flags:
   ```bash
   llama-server --help | grep -E 'ctx-checkpoints|spec-type|swa-full|chat-template-kwargs'
   ```

3. **curl**
   ```bash
   brew install curl
   ```

4. **Ollama** (optional — only for the legacy `ai-local 35b-ollama` backend)
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```
   Most users can skip this; llama.cpp is the default for both models.

## Install

```bash
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh
```

## Download models

llama.cpp GGUFs live under `~/.local/share/llama-models/`. The 35B MTP GGUF is required for the default 35B backend; the 27B MTP GGUF is recommended (+75% decode) but optional (a non-MTP 27B GGUF works as a fallback).

```bash
ai-local download 27b-mtp   # recommended: 27B + MTP (~18GB)
ai-local download 27b       # optional: 27B non-MTP fallback (~18GB)
ai-local download 35b       # 35B-A3B + MTP, 128k ctx (~22GB)
# Optional MLX backends (Apple Silicon):
ai-local download 27b-mlx
ai-local download 35b-mlx
```

> **Note:** the old Ollama 35B blob (`qwen3.6:35b-ud-q4xl`) cannot be reused for llama.cpp — Qwen3.6 changed `rope.dimension_sections` (3→4 elements), so llama-server rejects Ollama's old-layout blob. Re-download the GGUF above.

## Start services

```bash
ai-local 27b          # llama.cpp + MTP + checkpoint (default)
ai-local 35b          # llama.cpp + MTP + checkpoint, 128k ctx (default)
ai-local status
```

Optional backends:

```bash
ai-local 27b-mlx      # MLX alternative for 27B
ai-local 35b-mlx      # MLX alternative for 35B
ai-local 35b-ollama   # legacy Ollama backend (requires `ollama`)
```

Thinking mode:

```bash
AI_LOCAL_FORCE_THINK=1 ai-local 27b
AI_LOCAL_FORCE_THINK=1 ai-local 35b
```

> When thinking is on, `preserve_thinking=true` (set server-side via `--chat-template-kwargs`) keeps reasoning in history so the checkpoint cache can reuse prefixes across turns. See `docs/THINK_CONTROL.md`.

## Logs and diagnostics

```bash
ai-local logs 27b
ai-local logs 35b
ai-local logs 35b-llama   # llama-server 35B only
ai-local doctor
ai-local config
```

## Local overrides

Keep custom settings in:

```bash
cp config/.qwen-local.conf config/.qwen-local.conf.local
```

Only `.qwen-local.conf.local` should be edited for machine-specific values.
