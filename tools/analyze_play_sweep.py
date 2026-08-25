#!/usr/bin/env python3
"""Round-quality analyzer for a TIDBITS_PLAY_SWEEP capture.

The sweep drives the SHIPPED assembly (bundled corpus + shape sources + order)
across the mode × category grid and prints one PLAY-Q JSON line per delivered
question. The things that spoil a round are properties of the assembled ROUND,
not of any row — this asserts them at sweep scale:

  - round length: every game reaches its mode's expected count
  - no duplicate options within a question
  - no repeated question (prompt+answer) within one game
  - no empty prompt/answer/options
  - option list contains the answer (MCQ integrity)

Usage: python3 tools/analyze_play_sweep.py [build/qa/play-sweep.jsonl]
"""
import json, sys
from collections import defaultdict

path = sys.argv[1] if len(sys.argv) > 1 else "build/qa/play-sweep.jsonl"
games = defaultdict(list)
mode_of = {}
for line in open(path, errors="ignore"):
    if "PLAY-Q\t" not in line:
        continue
    try:
        d = json.loads(line.split("PLAY-Q\t", 1)[1])
    except json.JSONDecodeError:
        continue
    games[d.get("game")].append(d)
    if "mode" in d:
        mode_of[d.get("game")] = d["mode"]

problems = []
for g, qs in sorted(games.items()):
    qs.sort(key=lambda d: d.get("i", 0))
    mode = mode_of.get(g) or qs[0].get("mode", "?")
    seen = set()
    for d in qs:
        tag = f"game {g} q{d.get('i')}"
        prompt = (d.get("prompt") or "").strip()
        answer = (d.get("answer") or "").strip()
        opts = d.get("options") or []
        if not prompt:
            problems.append((g, f"{tag}: EMPTY prompt"))
        if not answer and opts:
            # Only MCQ-shaped rows carry a single answer; enumerate (list
            # recall, self-marked) legitimately has none.
            problems.append((g, f"{tag}: EMPTY answer"))
        if opts:
            if len(set(opts)) != len(opts):
                problems.append((g, f"{tag}: DUPLICATE options {opts}"))
            if answer and answer not in opts:
                problems.append((g, f"{tag}: answer {answer!r} not in options {opts}"))
        # A repeat the PLAYER experiences = same prompt AND same option set.
        # Template prompts ("Which is bigger by area?") legitimately recur with
        # different comparison pairs.
        key = (prompt, tuple(sorted(opts)) if opts else answer)
        if key in seen:
            problems.append((g, f"{tag}: REPEATED question {prompt[:60]!r} opts={opts}"))
        seen.add(key)

lengths = defaultdict(list)
for g, qs in games.items():
    lengths[mode_of.get(g, "?")].append(len(qs))

print(f"{len(games)} games, {sum(len(q) for q in games.values())} questions")
for m, ls in sorted(lengths.items()):
    lo, hi = min(ls), max(ls)
    note = "" if lo == hi else f"  <-- VARIABLE ({sorted(set(ls))})"
    print(f"  {m or '?':14s} {len(ls):3d} games, {lo}-{hi} questions{note}")

if problems:
    print(f"\n{len(problems)} problems:")
    for g, p in problems[:40]:
        print(" ", p)
else:
    print("\nNo round-integrity problems found.")
sys.exit(1 if problems else 0)
