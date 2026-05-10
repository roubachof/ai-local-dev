# Troubleshooting

## Services won't start

### llama-server fails to start

1. **Check if port is already in use:**
   ```bash
   lsof -i :8080
   ```

2. **Check logs:**
   ```bash
   tail -f /tmp/llama-server.log
   ```

3. **Verify model file exists:**
   ```bash
   ls -la ~/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf
   ```

4. **Restart services:**
   ```bash
   qwen-switch stop
   qwen-switch 27b
   ```

### Ollama won't start

1. **Check if ollama is installed:**
   ```bash
   which ollama
   ```

2. **Start manually:**
   ```bash
   ollama serve
   ```

3. **Pull model if missing:**
   ```bash
   ollama pull qwen3.6:35b-a3b
   ```

## Proxy issues

### Connection refused on proxy port

1. **Verify proxy is running:**
   ```bash
   # For 27B proxy
   curl -s http://127.0.0.1:8081/health
   
   # For 35B proxy
   curl -s http://127.0.0.1:11435/health
   ```

2. **Check proxy logs:**
   ```bash
   tail -f /tmp/proxy-27b.log
   tail -f /tmp/proxy-35b.log
   ```

3. **Start proxy manually:**
   ```bash
   # 27B proxy
   python3 bin/llama_nonthink_proxy.py --port 8081
   
   # 35B proxy
   python3 bin/ollama_nothink_proxy.py --port 11435
   ```

### Thinking not working

1. **Check environment variables:**
   ```bash
   echo $LLAMA_PROXY_FORCE_THINK   # Should be "1" to enable
   echo $OLLAMA_PROXY_FORCE_THINK  # Should be "1" to enable
   ```

2. **Restart proxy with thinking enabled:**
   ```bash
   qwen-switch stop
   LLAMA_PROXY_FORCE_THINK=1 qwen-switch 27b
   ```

## qwen-code issues

### Model not responding

1. **Check active model:**
   ```bash
   qwen-switch status
   ```

2. **Verify settings.json:**
   ```bash
   cat ~/.qwen/settings.json
   ```

3. **Restart qwen-code with correct model:**
   ```bash
   qwen-switch 27b  # or 35b
   q22
   ```

### Timeout errors

1. **Increase timeout in config:**
   Edit `config/.qwen-local.conf`:
   ```bash
   PROXY_TIMEOUT=1200  # 20 minutes
   ```

2. **Restart services:**
   ```bash
   qwen-switch stop
   qwen-switch 27b  # or 35b
   ```

## Common error messages

### "Model not found"

Download the missing model:
```bash
# For 27B (llama.cpp)
huggingface-cli download unsloth/Qwen3.6-27B-GGUF \
  Qwen3.6-27B-UD-Q4_K_XL.gguf \
  --local-dir ~/.local/share/llama-models

# For 35B (Ollama)
ollama pull qwen3.6:35b-a3b
```

### "Port already in use"

Find and kill the process:
```bash
# For port 8080 (llama-server)
lsof -i :8080
kill -9 <PID>

# For port 8081 (llama proxy)
lsof -i :8081
kill -9 <PID>

# For port 11434 (Ollama)
lsof -i :11434
kill -9 <PID>

# For port 11435 (Ollama proxy)
lsof -i :11435
kill -9 <PID>
```

### "Python module not found"

Install required dependencies:
```bash
cd /path/to/ai-local-dev
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi httpx uvicorn
```

## Getting help

1. **Check documentation:**
   - [`ARCHITECTURE.md`](ARCHITECTURE.md) - How proxies work
   - [`THINK_CONTROL.md`](THINK_CONTROL.md) - Enable/disable thinking
   - [`SETUP_FIRST_TIME.md`](SETUP_FIRST_TIME.md) - Fresh machine setup

2. **Report issues:** https://github.com/roubachof/ai-local-dev/issues
