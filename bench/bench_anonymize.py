#!/usr/bin/env python3
"""Merge two quality bench result files into a blind A/B side-by-side.

Randomizes which model is 'A' vs 'B' per prompt using a fixed seed so the
assignment is reproducible but blind. Writes:
  - bench/results/quality_blind.md   (the side-by-side to score from)
  - bench/results/quality_key.json   (the A/B -> model mapping; do NOT read
                                      this until scoring is complete)

Usage:
    python3 bench/bench_anonymize.py --a bench/results/quality_27b.json \\
                                      --b bench/results/quality_35b.json
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

RESULTS_DIR = Path(__file__).resolve().parent / "results"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--a", required=True, help="first model results (quality_X.json)")
    p.add_argument("--b", required=True, help="second model results (quality_Y.json)")
    p.add_argument("--label-a", default="A_FILE", help="true name of model in --a")
    p.add_argument("--label-b", default="B_FILE", help="true name of model in --b")
    p.add_argument("--seed", type=int, default=20260622)
    p.add_argument("--suffix", default="", help="suffix for output files (e.g. '_think')")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    a = json.loads(Path(args.a).read_text())
    b = json.loads(Path(args.b).read_text())
    a_by_id = {r["id"]: r for r in a["results"]}
    b_by_id = {r["id"]: r for r in b["results"]}
    ids = [r["id"] for r in a["results"]]

    rng = random.Random(args.seed)
    mapping: dict[str, dict] = {}
    lines: list[str] = []
    lines.append("# Quality bench — blind A/B side-by-side")
    lines.append("")
    lines.append(f"Prompt set: {len(ids)} prompts. A/B assignment randomized per "
                 f"prompt (seed={args.seed}). Score each response independently "
                 f"before consulting quality_key.json.")
    lines.append("")
    lines.append("## Rubric (0-7 per response)")
    lines.append("- **Correctness (0-3):** 0 = wrong, 1 = partially right, "
                 "2 = right but with a flaw/gap, 3 = fully correct.")
    lines.append("- **Completeness (0-2):** 0 = missing key parts, 1 = mostly "
                 "complete, 2 = complete per the prompt's ask.")
    lines.append("- **Clarity (0-2):** 0 = unclear/messy, 1 = clear enough, "
                 "2 = clear and well-structured.")
    lines.append("- Total = Correctness + Completeness + Clarity (0-7).")
    lines.append("")

    for pid in ids:
        ra = a_by_id.get(pid)
        rb = b_by_id.get(pid)
        if ra is None or rb is None:
            continue
        # Randomize: with prob 0.5, swap which file's response is 'A'.
        swap = rng.random() < 0.5
        first, second = (rb, ra) if swap else (ra, rb)
        first_file, second_file = ("b_file", "a_file") if swap else ("a_file", "b_file")
        # Record the true mapping (A -> which true label).
        mapping[pid] = {
            "A": args.label_b if swap else args.label_a,
            "B": args.label_a if swap else args.label_b,
        }
        prompt = ra.get("prompt", "")
        cat = ra.get("category", "")
        lines.append(f"---")
        lines.append("")
        lines.append(f"## [{pid}] {cat}  (max_tokens={ra.get('max_tokens')})")
        lines.append("")
        lines.append("**Prompt:**")
        lines.append("")
        lines.append(prompt)
        lines.append("")
        lines.append(f"**Response A** (comp={first.get('completion_tokens')}, "
                     f"finish={first.get('finish_reason')})")
        lines.append("")
        lines.append("```")
        lines.append(first.get("response", "") or "(empty)")
        lines.append("```")
        lines.append("")
        lines.append(f"**Response B** (comp={second.get('completion_tokens')}, "
                     f"finish={second.get('finish_reason')})")
        lines.append("")
        lines.append("```")
        lines.append(second.get("response", "") or "(empty)")
        lines.append("")
        lines.append("Scores: A=correctness[__]/3 completeness[__]/2 clarity[__]/2  "
                     "B=correctness[__]/3 completeness[__]/2 clarity[__]/2")
        lines.append("")

    suffix = args.suffix
    (RESULTS_DIR / f"quality_blind{suffix}.md").write_text("\n".join(lines))
    (RESULTS_DIR / f"quality_key{suffix}.json").write_text(
        json.dumps({"seed": args.seed,
                    "a_file_label": args.label_a,
                    "b_file_label": args.label_b,
                    "mapping": mapping}, indent=2))
    print(f"Wrote {RESULTS_DIR/f'quality_blind{suffix}.md'}")
    print(f"Wrote {RESULTS_DIR/f'quality_key{suffix}.json'} (do not read until scored)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
