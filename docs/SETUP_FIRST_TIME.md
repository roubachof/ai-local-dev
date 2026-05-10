# Setup First Time Guide

## Prerequisites

Before installing `ai-local-dev`, ensure you have the following installed:

### Required

1. **Python 3.11+**
   ```bash
   # macOS
   brew install python@3.11
   
   # Ubuntu/Debian
   sudo apt install python3.11 python3.11-venv
   ```

2. **Ollama** (for 35B model)
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```

3. **llama-server** (for 27B model)
   ```bash
   # From llama.cpp
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   make -j
   sudo cp llama-server /usr/local/bin/
   ```

4. **curl**
   ```bash
   # macOS
   brew install curl
   
   # Ubuntu/Debian
   sudo apt install curl
   ```

5. **Node.js 22+** (for qwen-code)
   ```bash
   # Using nvm
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
   nvm install 22
   ```

### Optional

- **zsh** (recommended over bash)
- **jq** (for JSON processing in scripts)

## Download Models

### Qwen3.6-35B-A3B (Ollama)

```bash
ollama pull qwen3.6:35b-a3b
```

### Qwen3.6-27B (llama.cpp GGUF)

```bash
# Create models directory
mkdir -p ~/.local/share/llama-models

# Download from HuggingFace
huggingface-cli download unsloth/Qwen3.6-27B-GGUF \
  Qwen3.6-27B-UD-Q4_K_XL.gguf \
  --local-dir ~/.local/share/llama-models
```

## Install ai-local-dev

```bash
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh
```

## Verify Installation

```bash
# Check status
ai-local status

# Start 27B model
ai-local 27b

# Start 35B model
ai-local 35b

# Launch Goose
ai-local goose
```

## Next Steps

1. Launch Goose: `ai-local goose`
2. Launch with thinking: `ai-local goose think`
3. Check logs: `tail -f /tmp/llama-server.log` or `tail -f /tmp/proxy-27b.log`
4. Customize config: `cp config/.qwen-local.conf config/.qwen-local.conf.local` and edit
