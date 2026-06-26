#!/usr/bin/env python3
"""Quality benchmark for the 27B/35B llama.cpp stack.

Sends a fixed 20-prompt suite (7 categories: debug, impl, design, reasoning,
math, explanation, writing) through the no-think proxy and saves each response
with its usage/wall-time. Run once per model, then combine with
bench_anonymize.py to produce a blind side-by-side for scoring.

Usage:
    python3 bench/bench_quality.py --url http://127.0.0.1:8081/v1 --label 27b
    python3 bench/bench_quality.py --url http://127.0.0.1:11435/v1 --label 35b

Results are written to bench/results/quality_<label>.json.
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import httpx

# Each prompt: (id, category, prompt, max_tokens).
# max_tokens tuned per category so the model has room to answer fully without
# hitting the cap on every prompt (which would make scoring impossible).
PROMPTS: list[tuple[str, str, str, int]] = [
    # ---- debug (find the bug) ----
    ("dbg1", "debug",
     "Find the bug in this Python function and give the fix in one sentence plus corrected code:\n\n```python\ndef merge_sorted(a, b):\n    result = []\n    i = j = 0\n    while i < len(a) and j < len(b):\n        if a[i] < b[j]:\n            result.append(a[i]); i += 1\n        else:\n            result.append(b[j]); j += 1\n    return result\n```", 600),
    ("dbg2", "debug",
     "What is wrong with this SQL, and how would you fix it? One sentence + corrected SQL.\n\n```sql\nSELECT users.name, COUNT(orders.id)\nFROM users\nWHERE orders.user_id = users.id\nGROUP BY users.name\nORDER BY COUNT(orders.id) DESC\n```", 600),
    ("dbg3", "debug",
     "This async Python code occasionally loses tasks. Find the bug and give the fix in one sentence plus code.\n\n```python\nimport asyncio\nasync def process(items):\n    results = []\n    for x in items:\n        asyncio.create_task(handle(x))\n    return results\n```", 600),

    # ---- impl (write code) ----
    ("imp1", "impl",
     "Write a Python `debounce` decorator like lodash's debounce: the returned function delays execution until `wait` seconds after the last call, and only the last call's args are used. Type hints, <25 lines.", 700),
    ("imp2", "impl",
     "Implement a Python class `RateLimiter` with a token-bucket algorithm: `allow(n=1)` returns True if n tokens are available (refilling at `rate` tokens/sec up to `capacity`). Type hints, <30 lines.", 700),
    ("imp3", "impl",
     "Write a Python function `flatten(obj)` that deep-flattens nested lists/tuples of arbitrary depth into a flat list, but yields dict values in place (does not recurse into dicts). Handle strings as atoms, not iterables. <20 lines.", 700),

    # ---- design (architecture/tradeoffs) ----
    ("des1", "design",
     "In Python, when should you use asyncio vs threading? One concrete example of each and the main tradeoff in one line.", 700),
    ("des2", "design",
     "You are designing a URL shortener expected to handle 100M shortened URLs and ~1k redirects/sec. Describe the data model, the read path, and one scaling risk. <200 words.", 700),
    ("des3", "design",
     "When building a CLI tool in Go vs Rust, what are the main tradeoffs? Give one situation where each is the better pick.", 700),

    # ---- reasoning (logical/causal) ----
    ("rea1", "reasoning",
     "A bat and a ball cost $1.10 in total. The bat costs $1.00 more than the ball. How much does the ball cost? Show your reasoning in 2-3 lines.", 300),
    ("rea2", "reasoning",
     "If all Bloops are Razzies and all Razzies are Lazzies, is it necessarily true that all Bloops are Lazzies? Explain in one sentence why or why not.", 300),
    ("rea3", "reasoning",
     "You have 3 boxes labeled 'apples', 'oranges', and 'mixed'. Every label is WRONG. You may pull one fruit from one box. How do you label all three correctly? Explain the reasoning.", 500),

    # ---- math ----
    ("mat1", "math",
     "Solve step by step: a train travels 60 km/h for 2 hours, then 80 km/h for 1.5 hours. What is the average speed for the whole journey? Show your work.", 500),
    ("mat2", "math",
     "How many ways can you arrange the letters in the word BANANA? Show your reasoning.", 500),
    ("mat3", "math",
     "Simplify and explain: what is the value of log2(8) + log2(32) - log2(2)?", 400),

    # ---- explanation (teach a concept) ----
    ("exp1", "explanation",
     "Explain how transformer attention works to a competent software engineer new to ML. Cover Q/K/V, softmax, and why scaling is needed. <150 words.", 700),
    ("exp2", "explanation",
     "What is the difference between TCP and UDP? List 4 concrete differences.", 600),
    ("exp3", "explanation",
     "Explain what a Python decorator does, using a non-trivial real example (not just logging). <120 words.", 600),

    # ---- writing (creative/structured) ----
    ("wri1", "writing",
     "Summarize the plot of Mary Shelley's Frankenstein in exactly 4 sentences.", 400),
    ("wri2", "writing",
     "Write a short poem (8 lines) about a lighthouse keeper who discovers a message in a bottle.", 300),
    ("wri3", "writing",
     "Write a 3-line professional email declining a meeting invitation politely, suggesting an async alternative.", 300),
]

RESULTS_DIR = Path(__file__).resolve().parent / "results"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", default="http://127.0.0.1:8081/v1")
    p.add_argument("--label", default="run")
    p.add_argument("--model", default="qwen")
    p.add_argument("--max-tokens-mult", type=float, default=1.0,
                   help="multiply each prompt's max_tokens by this (e.g. 4 for "
                        "thinking-mode runs where reasoning consumes the budget)")
    return p.parse_args()


def run_one(client: httpx.Client, url: str, model: str, pid: str, category: str,
            prompt: str, max_tokens: int) -> dict:
    t0 = time.perf_counter()
    resp = client.post(
        f"{url}/chat/completions",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0.6,
            "top_p": 0.95,
            "stream": False,
        },
        timeout=600.0,
    )
    wall = time.perf_counter() - t0
    resp.raise_for_status()
    data = resp.json()
    usage = data.get("usage", {})
    content = data["choices"][0]["message"]["content"]
    finish = data["choices"][0].get("finish_reason", "")
    return {
        "id": pid,
        "category": category,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "response": content,
        "finish_reason": finish,
        "wall_s": round(wall, 2),
        "completion_tokens": usage.get("completion_tokens", 0),
        "prompt_tokens": usage.get("prompt_tokens", 0),
    }


def main() -> int:
    args = parse_args()
    print(f"=== quality {args.label} | {args.url} | {len(PROMPTS)} prompts | max_tokens_mult={args.max_tokens_mult} ===")
    results = []
    with httpx.Client() as client:
        for pid, category, prompt, max_tokens in PROMPTS:
            effective_max = int(max_tokens * args.max_tokens_mult)
            try:
                r = run_one(client, args.url, args.model, pid, category, prompt, effective_max)
                r["max_tokens"] = effective_max
                results.append(r)
                capped = " [CAPPED]" if r["finish_reason"] == "length" else ""
                print(f"  {pid:5s} {category:11s} wall={r['wall_s']:6.1f}s "
                      f"comp={r['completion_tokens']:4d}{capped}")
            except Exception as e:  # noqa: BLE001
                print(f"  {pid:5s} {category:11s} ERROR: {e}")
                results.append({"id": pid, "category": category, "prompt": prompt,
                                "error": str(e)})
            time.sleep(0.5)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS_DIR / f"quality_{args.label}.json"
    out_path.write_text(json.dumps({"label": args.label, "url": args.url,
                                    "max_tokens_mult": args.max_tokens_mult,
                                    "results": results}, indent=2, ensure_ascii=False))
    print(f"Saved -> {out_path}")
    capped = sum(1 for r in results if r.get("finish_reason") == "length")
    print(f"Capped (finish_reason=length): {capped}/{len(results)}")
    return 0 if results else 1


if __name__ == "__main__":
    raise SystemExit(main())
