# Think Control

## Overview
`ai-local-dev` runs with thinking disabled by default for latency and cost savings. The proxy can be flipped to force-thinking mode with an environment variable.

## Disable mechanism (current behavior)
For `POST /v1/chat/completions`, the unified proxy applies:

- `chat_template_kwargs.enable_thinking=false` (Qwen template-level switch, used by llama.cpp)
- `enable_thinking=false` (legacy fallback key)
- `think=false` and `reasoning_effort=none` (defense-in-depth for Ollama)

The proxy also strips `<think>...</think>` blocks from response `content` in both JSON and SSE streaming responses when thinking is disabled.

## Enable thinking
Canonical switch:

```bash
AI_LOCAL_FORCE_THINK=1 ai-local 27b
AI_LOCAL_FORCE_THINK=1 ai-local 35b
```

Legacy aliases are still supported:

- `LLAMA_PROXY_FORCE_THINK=1`
- `OLLAMA_PROXY_FORCE_THINK=1`
- `OLLAMA_PROXY_THINK=1`

## preserve_thinking and checkpoint cache
When thinking is on, llama-server is started with `--chat-template-kwargs {"preserve_thinking": true}` (controlled by `LLAMA_PRESERVE_THINKING=1`, default on). This keeps reasoning in the conversation history so the hybrid-cache checkpoint (`--ctx-checkpoints`) can reuse prefixes across turns. Without `preserve_thinking`, the chat template strips reasoning from history on each turn and the prefix changes every turn — the checkpoint then can't be reused and every turn re-prefills the full context.

The proxy's nothink `enable_thinking=false` is orthogonal to `preserve_thinking`: the former only governs whether the *current* turn reasons; the latter governs how history reasoning is rendered for cache reuse.

## Logs
All runtime logs are now under:

- `~/.local/state/ai-local/logs/proxy-27b.log`
- `~/.local/state/ai-local/logs/proxy-35b.log`

You can tail them with:

```bash
ai-local logs 27b
ai-local logs 35b
ai-local logs 35b-llama   # llama-server 35B only
```
