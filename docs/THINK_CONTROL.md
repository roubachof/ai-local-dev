# Think Control

## Overview
`ai-local-dev` runs with thinking disabled by default for latency and cost savings. The proxy can be flipped to force-thinking mode with an environment variable.

## Disable mechanism (current behavior)
For `POST /v1/chat/completions`, the unified proxy applies:

- `chat_template_kwargs.enable_thinking=false` (Qwen template-level switch, used by llama.cpp and MLX)
- `enable_thinking=false` (legacy fallback key)
- `think=false` and `reasoning_effort=none` (defense-in-depth for Ollama)

The proxy also strips `<think>...</think>` blocks from response `content` in both JSON and SSE streaming responses when thinking is disabled.

## Enable thinking
Canonical switch:

```bash
AI_LOCAL_FORCE_THINK=1 ai-local 27b
AI_LOCAL_FORCE_THINK=1 ai-local 8b
AI_LOCAL_FORCE_THINK=1 ai-local 35b
```

Legacy aliases are still supported:

- `LLAMA_PROXY_FORCE_THINK=1`
- `OLLAMA_PROXY_FORCE_THINK=1`
- `OLLAMA_PROXY_THINK=1`

## Verify that thinking is really disabled
Use the regression script:

```bash
bin/verify_nothink.sh
```

It compares nothink vs force-think on both proxies and fails if:

- nothink completion tokens are not at least 5x smaller than force-think
- nothink latency is not at least 2x faster than force-think

## Logs
All runtime logs are now under:

- `~/.local/state/ai-local/logs/proxy-27b.log`
- `~/.local/state/ai-local/logs/proxy-35b.log`

You can tail them with:

```bash
ai-local logs 27b
ai-local logs 8b
ai-local logs 35b
```
