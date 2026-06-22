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

## Install

```bash
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh
```

## Download models

llama.cpp GGUFs live under `~/.local/share/llama-models/`. The 35B MTP GGUF is required for the default 35B backend; the 27B MTP GGUF is the default 27B model file (MTP speculative decoding is on by default — see `bench/README.md`; a non-MTP 27B GGUF works as an alternate).

```bash
ai-local download 27b-mtp   # 27B MTP GGUF (default model file, ~18GB)
ai-local download 27b       # optional: 27B non-MTP GGUF (~18GB)
ai-local download 35b       # 35B-A3B + MTP, 128k ctx (~22GB)
```

## Start services

```bash
ai-local 27b          # llama.cpp + checkpoint + MTP (on by default)
ai-local 35b          # llama.cpp + checkpoint + MTP, 128k ctx
ai-local status
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
