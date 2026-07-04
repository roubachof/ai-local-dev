# Running the 27B on a Windows NVIDIA GPU (RTX 4080 / 16 GB)

The 27B dense is bandwidth-bound: on the M3 Max (~400 GB/s unified memory) it tops
out around 14–15 tok/s, while the 35B-A3B MoE (~66 tok/s) is the better daily driver
there. A discrete NVIDIA GPU changes the calculus — the RTX 4080 has ~717 GB/s of
GDDR6X and CUDA's single-batch decode efficiency is markedly higher than Metal's —
so the 27B dense finally gets fast *there*.

The catch is VRAM: the 4080 has **16 GB**, and the 27B in the Mac's `UD-Q4_K_XL`
quant is ~18 GB of weights — it does not fit. You must drop to a 3-bit quant so the
whole model + KV cache + MTP draft context fits in VRAM (no PCIe spill). **IQ3_XXS
is the recommended quant**: it is the highest-quality 3-bit Unsloth Dynamic variant,
and combined with the MTP head it is the documented "dream config" for 16 GB cards —
a 27B dense model that fits entirely on GPU with free speculative decoding.

This is a *test plan* to run when you are on the Windows machine. The Mac stack
(`ai-local 35b`) is untouched — this is an additional, remote 27B backend.

## Expected ballpark (16 GB GPU, IQ3_XXS + MTP)

Reference datapoint from a published 16 GB run (RTX 5080, community-grafted IQ3_XXS+MTP):
**76 tok/s with MTP, 53 tok/s without, 90.6 % draft acceptance, GSM8K 89/100**.
The 4080 has less memory bandwidth than the 5080 (~717 vs ~960 GB/s), so expect
roughly **55–65 tok/s** with MTP — bench to confirm. Either way that is ~4× the
Mac's 15 tok/s, at the cost of running a 3-bit quant (measure the quality hit with
`bench/bench_quality.py`).

Hard limit on 16 GB: **max stable context ~32 k with q8_0 KV, ~56 k with q4_0 KV**
beyond that the MTP compute buffer OOMs. This remote 27B is therefore a
short/medium-context fast dense server — it does **not** replace the Mac 35B's 128 k
long-context role.

## Prerequisites (Windows)

1. **NVIDIA driver + CUDA toolkit**. ⚠️ **Do NOT use CUDA 13.2** — it produces
   gibberish outputs with Qwen3.6 (confirmed by Unsloth). Use CUDA < 13.2 or
   CUDA 13.3+.
2. **Visual Studio 2019/2022 Build Tools** (C++ workload) — required to build
   llama.cpp with CUDA.
3. **CMake** and **git**.
4. **huggingface-cli** for the download:
   ```powershell
   pip install "huggingface-hub[hf_transfer]"
   ```

## Get llama-server (CUDA build)

Build from source (recommended, so you get build 9750+ with the MTP + hybrid flags
this repo relies on):

```powershell
git clone https://github.com/ggml-org/llama.cpp
cmake -S llama.cpp -B llama.cpp/build -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=ON
cmake --build llama.cpp/build --config Release -j --clean-first --target llama-server
```

(Alternatively, use a prebuilt Windows CUDA binary from the llama.cpp releases — but
confirm it is build 9750+ or `--spec-type draft-mtp` / `--ctx-checkpoints` may be
missing.)

Verify the build exposes the flags:
```powershell
llama-server --help | findstr /R "spec-type ctx-checkpoints swa-full"
```

## Download the model (IQ3_XXS, MTP head)

**Option A — Unsloth MTP repo (single source, matches the Mac `ai-local download`
flow).** This is the Unsloth Dynamic IQ3_XXS with the MTP head:

```powershell
huggingface-cli download unsloth/Qwen3.6-27B-MTP-GGUF `
    --include "*UD-IQ3_XXS*" `
    --local-dir D:\models\qwen27b-iq3xxs-mtp
```

If `--spec-type draft-mtp` later fails to load (missing `nextn` tensors / 64 blocks),
the file in that snapshot did not carry the MTP head — fall back to Option B.

**Option B — Community-grafted MTP IQ3_XXS (MTP guaranteed, published 16 GB
numbers).** `GazTrab/Qwen3.6-27B-MTP-UD-IQ3_XXS-GGUF` is Unsloth IQ3_XXS with the
MTP head grafted in (65 blocks, 12.45 GB, SHA256-verified). Use this if Option A's
MTP head is missing:

```powershell
huggingface-cli download GazTrab/Qwen3.6-27B-MTP-UD-IQ3_XXS-GGUF `
    --include "*.gguf" `
    --local-dir D:\models\qwen27b-iq3xxs-mtp
```

## Launch llama-server on the Windows GPU

Bind to `0.0.0.0` so the Mac can reach it over the LAN. MTP requires `-np 1` and is
incompatible with `--mmproj` (no vision on this endpoint). PowerShell quoting for the
chat-template kwargs is different from bash — use backslash-escaped double quotes.

```powershell
llama-server `
    -m D:\models\qwen27b-iq3xxs-mtp\Qwen3.6-27B-UD-IQ3_XXS.gguf `
    --host 0.0.0.0 --port 8080 `
    -ngl 99 -c 32768 -np 1 -fa on --no-mmap --jinja `
    -ctk q8_0 -ctv q8_0 `
    --ctx-checkpoints 128 --swa-full `
    --chat-template-kwargs "{\"preserve_thinking\": true}" `
    --spec-type draft-mtp --spec-draft-n-max 2 `
    --temp 0.6 --top-p 0.95 --top-k 20
```

Notes on the flags:
- `-c 32768` with `q8_0` KV is the stable 16 GB config. For longer context use
  `-c 57344 -ctk q4_0 -ctv q4_0` (extends stable ctx to ~56 k; q4_0 KV is
  near-lossless per the CodeNeedle recall test on this exact model).
- `--spec-draft-n-max 2` is Unsloth's general recommendation; the Mac stack uses 3
  for the 27B. Try 2 then 3 and keep whichever benches faster on the 4080.
- `--ctx-checkpoints 128 --swa-full` are the same Qwen3.6 hybrid-cache multi-turn
  prefill fix the Mac stack uses (`docs/ARCHITECTURE.md`). Drop them only if your
  build does not accept them.
- For **no-think** mode (the `ai-local` default), add
  `--chat-template-kwargs "{\"enable_thinking\": false}"` (replace, not combine,
  with `preserve_thinking`).

Verify locally on Windows:
```powershell
curl http://127.0.0.1:8080/v1/models
```

## Benchmark it from the Mac

Point the existing bench scripts at the Windows endpoint (no stack to start on the
Mac — just hit the remote URL). Replace `192.168.x.x` with the Windows machine's LAN
IP.

```bash
# Throughput + draft acceptance (scrapes the remote llama-server log is NOT possible
# over HTTP, so the spec_types field will be empty — confirm MTP via the Windows log)
python3 bench/bench_mtp.py --url http://192.168.x.x:8080/v1 --label 27b-win4080-iq3xxs-mtp

# Quality comparison vs the Mac Q4_K_XL 27B (decide if the 3-bit quality is acceptable)
python3 bench/bench_quality.py --url http://192.168.x.x:8080/v1 --label 27b-win4080-iq3xxs
```

To confirm MTP actually engaged, check the Windows `llama-server` console for the
`statistics draft-mtp:` line and the `draft acceptance = ...` rate (the bench's
`spec_types` scraper reads the *local* log path, which does not exist on the Mac for
a remote backend).

## Connect the Mac workflow

- **Direct (LAN):** point Warp / OpenCode at `http://192.168.x.x:8080/v1` with any
  placeholder API key. Simplest.
- **Tunneled (off-LAN):** expose the Windows port with ngrok and use the public URL,
  mirroring `docs/NGROK_ENDPOINTS.md` (run ngrok on the Windows side:
  `ngrok http --host-header=rewrite 8080`).

The Mac `ai-local` proxy is not required here — the Windows `llama-server` already
exposes an OpenAI-compatible `/v1`. If you later want the no-think stripping /
context-pressure warnings from `bin/__proxy.py` in front of the Windows backend, run
just the proxy on the Mac with `--upstream-url http://192.168.x.x:8080` (the launcher
hardcodes localhost upstreams, so this needs a small config tweak — not covered here).

## Caveats

- **16 GB VRAM caps context at ~56 k.** This remote 27B is for fast short/medium
  context work; keep the Mac 35B-A3B for 128 k long-context jobs.
- **CUDA 13.2 corrupts Qwen3.6 output.** Use < 13.2 or ≥ 13.3.
- **MTP is single-slot, no vision:** `-np 1` and no `--mmproj` while MTP is on.
- **Quality is 3-bit.** IQ3_XXS is the best-behaved 3-bit variant, but it is still a
  step down from the Mac's Q4_K_XL. Run `bench/bench_quality.py` against both before
  trusting the 27B-on-Windows for quality-sensitive tasks.
- **PowerShell quoting:** `--chat-template-kwargs` uses `"{\"key\": value}"`, not
  bash's `'{"key": value}'`.
- **`--spec-type mtp` is the old alias.** Build 9750 wants `--spec-type draft-mtp`
  (this repo's canonical form).
