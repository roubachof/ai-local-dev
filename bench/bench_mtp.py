#!/usr/bin/env python3
"""Benchmark MTP vs non-MTP on the 27B (or 35B) llama.cpp stack.

Sends a fixed set of prompts through the proxy, measures generation tok/s
from the OpenAI usage fields + wall time. Run once with MTP on, once with
MTP off, compare. Also scrapes draft acceptance from the llama-server log.

Usage:
    python3 bench/bench_mtp.py [--url http://127.0.0.1:8081/v1] [--label run-mtp-on]

Results are written to bench/results/bench_<label>.json.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import httpx

PROMPTS = [
    ("code_python", "Write a Python function that returns the nth Fibonacci number using memoization. Include a brief explanation."),
    ("code_cpp", "Write a C++ function to reverse a singly linked list. Include the struct definition."),
    ("explain_concept", "Explain how transformer attention works, as if to a competent software engineer who is new to ML. Cover Q/K/V, softmax, and why scaling is needed."),
    ("summarize", "Summarize the plot of Mary Shelley's Frankenstein in 4 sentences."),
    ("qa_factual", "What are the main differences between TCP and UDP? List at least 4 points."),
    ("creative_short", "Write a short poem (8 lines) about a lighthouse keeper who discovers a message in a bottle."),
    ("stepwise_math", "Solve step by step: a train travels 60 km/h for 2 hours, then 80 km/h for 1.5 hours. What is the average speed for the whole journey? Show your work."),
    ("long_code_review", "Review this Python snippet for bugs and style: `def fib(n): a,b=0,1; [a,b]=[b,a+b] for _ in range(n); return a`. List 3 issues."),
]

LOG_PATH = Path.home() / ".local/state/ai-local/logs/llama-server.log"
RESULTS_DIR = Path(__file__).resolve().parent / "results"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", default="http://127.0.0.1:8081/v1")
    p.add_argument("--label", default="run")
    p.add_argument("--max-tokens", type=int, default=192)
    p.add_argument("--model", default="qwen")
    return p.parse_args()


def scrape_draft_acceptance() -> dict:
    """Read the llama-server log tail and extract draft/accept stats."""
    if not LOG_PATH.exists():
        return {}
    text = LOG_PATH.read_text(errors="replace")
    # llama-server prints periodic spec stats like:
    #   "draft ... accepted ... rate=0.72" or similar. Patterns vary by build;
    #   grab the most recent aggregate-ish numbers we can find.
    out = {}
    m = re.findall(r"acc[ept]*[=:]?\s*(\d+)\s*.*?draft[=:]?\s*(\d+)", text, re.I)
    if m:
        acc, draft = m[-1]
        out["last_draft"] = int(draft)
        out["last_accepted"] = int(acc)
        if int(draft) > 0:
            out["last_accept_rate"] = round(int(acc) / int(draft), 3)
    return out


def run_one(client: httpx.Client, url: str, model: str, prompt: str, max_tokens: int) -> dict:
    t0 = time.perf_counter()
    resp = client.post(
        f"{url}/chat/completions",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "stream": False,
            "temperature": 0.6,
            "top_p": 0.95,
        },
        timeout=600.0,
    )
    wall = time.perf_counter() - t0
    resp.raise_for_status()
    data = resp.json()
    usage = data.get("usage", {})
    comp = usage.get("completion_tokens", 0)
    prompt_tok = usage.get("prompt_tokens", 0)
    tok_s = comp / wall if wall > 0 else 0.0
    return {
        "wall_s": round(wall, 2),
        "completion_tokens": comp,
        "prompt_tokens": prompt_tok,
        "tok_s": round(tok_s, 2),
    }


def main() -> int:
    args = parse_args()
    print(f"=== {args.label} | {args.url} | max_tokens={args.max_tokens} ===")
    results = []
    with httpx.Client() as client:
        for name, prompt in PROMPTS:
            try:
                r = run_one(client, args.url, args.model, prompt, args.max_tokens)
                r["name"] = name
                results.append(r)
                print(f"  {name:20s} wall={r['wall_s']:6.2f}s  comp={r['completion_tokens']:4d}  tok/s={r['tok_s']:6.2f}")
            except Exception as e:
                print(f"  {name:20s} ERROR: {e}", file=sys.stderr)
                results.append({"name": name, "error": str(e)})
            time.sleep(1)  # let KV settle between prompts
    # aggregate
    ok = [r for r in results if "tok_s" in r]
    if ok:
        total_comp = sum(r["completion_tokens"] for r in ok)
        total_wall = sum(r["wall_s"] for r in ok)
        agg_tok_s = total_comp / total_wall if total_wall > 0 else 0.0
        print()
        print(f"Aggregate: n={len(ok)}  total_comp={total_comp}  total_wall={total_wall:.2f}s  agg_tok/s={agg_tok_s:.2f}")
    draft = scrape_draft_acceptance()
    if draft:
        print(f"Draft acceptance (from log): {draft}")
    # save json
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS_DIR / f"bench_{args.label}.json"
    out_path.write_text(json.dumps({"label": args.label, "results": results, "aggregate_tok_s": agg_tok_s if ok else None, "draft_acceptance": draft}, indent=2))
    print(f"Saved -> {out_path}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
