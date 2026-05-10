# Think Control

## Overview

Both proxies in `ai-local-dev` disable model thinking by default, but you can **enable thinking at runtime** using environment variables.

## How It Works

### Qwen3.6-35B-A3B (Ollama)

**Default behavior:** Injects `reasoning_effort:"none"` into requests → thinking OFF

**Enable thinking:**
```bash
OLLAMA_PROXY_FORCE_THINK=1 qwen-switch 35b
```

### Qwen3.6-27B (llama-server)

**Default behavior:** Sets `enable_thinking:false` and strips `reasoning_content` from responses → thinking OFF

**Enable thinking:**
```bash
LLAMA_PROXY_FORCE_THINK=1 qwen-switch 27b
```

## When to Enable Thinking

| Scenario | Recommendation |
|----------|---------------|
| Simple tasks (code formatting, Q&A) | ❌ Keep thinking OFF (faster, cheaper) |
| Complex reasoning (math, logic puzzles) | ✅ Enable thinking |
| Debugging difficult problems | ✅ Enable thinking |
| Long conversations with deep analysis | ✅ Enable thinking |

## Troubleshooting

### Thinking not enabled even with FORCE_THINK=1

1. **Restart the proxy:**
   ```bash
   qwen-switch stop
   OLLAMA_PROXY_FORCE_THINK=1 qwen-switch 35b
   ```

2. **Check proxy logs:**
   ```bash
   tail -f /tmp/proxy-35b.log   # Ollama proxy
   tail -f /tmp/proxy-27b.log   # llama-server proxy
   ```

3. **Verify environment variable is set:**
   ```bash
   echo $OLLAMA_PROXY_FORCE_THINK  # Should output "1"
   echo $LLAMA_PROXY_FORCE_THINK   # Should output "1"
   ```

### Thinking enabled but not seeing reasoning output

- For **llama-server (27B)**: The proxy strips `reasoning_content` from responses. When thinking is enabled, you'll see the full response including reasoning in the `content` field.
- For **Ollama (35B)**: The proxy injects `reasoning_effort:"none"`. When thinking is enabled, it sends the request without modification, allowing the model to include reasoning tags.

## Permanent Configuration

To always enable thinking for a specific proxy, add to your `~/.zshrc`:

```bash
# Always enable thinking for 27B model
export LLAMA_PROXY_FORCE_THINK=1

# Always enable thinking for 35B model
export OLLAMA_PROXY_FORCE_THINK=1
```

Then restart your terminal or run: `source ~/.zshrc`
