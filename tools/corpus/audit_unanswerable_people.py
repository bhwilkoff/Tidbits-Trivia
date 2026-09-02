"""Bare comparison questions whose options are ALL obscure PEOPLE.

    Which of these is a chemist?
      Edith Anne Stoney / Vernon Louis Parrington / Alice Freeman Palmer / Elizabeth Rona

A player recognises none of the four and the prompt states no fact to reason
from, so it is a coin flip that teaches nothing. Both halves are required:

  * BARE prompt — a short "which/who...?" with no descriptive clause. A rich
    prompt makes an obscure answer FINE, because the question carries its own
    context and the player learns something. "Charted in 1756 by Lacaille and
    named for the drafting tool that draws circles, this faint southern
    constellation..." is a good question with a very obscure answer.
  * every option a PERSON, and even the best-known below the floor.

WHY PEOPLE ONLY, AND WHY THE FLOOR IS THIS LOW. qrank is Wikipedia pageview
rank, and it is NOT comparable across entity types: "Good Vibrations" scores
497k and four US national parks score ~211k, while being far more familiar than
a person at the same number. Reading the boundary proved a global floor
destroys good questions --- at 1M it cuts "Which of these was founded earliest?
Southwest / Alaska / Norse Atlantic / Pegasus"; at 800k it cuts "Who directed
Pink Floyd - The Wall?" over four recognisable directors; at 250k it cuts
"Which one below is largest in area?" over four national parks. Restricted to
PEOPLE, where the proxy is fair, the extreme low end is unambiguous.

    python3 tools/corpus/audit_unanswerable_people.py           # report
    python3 tools/corpus/audit_unanswerable_people.py --write   # write tombstones
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"
SOURCE_DB = ROOT / "tools/corpus/corpus_source.sqlite"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"

# Read the boundary before touching this. 250k was the first candidate and the
# read rejected it: its top band held ANSWERABLE questions -- Charles Rennie
# Mackintosh (227k) is a famous architect, Donna Strickland (208k) a Nobel
# laureate, Carl Zeiss (225k) a household optics name. Every hit at or below
# 150k is a genuine coin flip. The cost of cutting a good question is higher
# than the cost of leaving a bad one for the next pass, so the floor sits where
# precision is clean, not where recall is largest.
QRANK_FLOOR = 150_000
BARE = re.compile(r"^(which|who|what)[^?]{0,70}\?$", re.I)


def offenders():
    con = sqlite3.connect(SOURCE_DB)
    sub = {t: (q, p or "") for t, q, p in
           con.execute("select title, qrank, p31 from subject")}
    rows = json.loads(CORPUS_JSON.read_text())["questions"]

    out = []
    for r in rows:
        qid, prompt, opts = r[0], r[1], r[2]
        if not isinstance(opts, list) or len(opts) < 2:
            continue
        if not BARE.match(prompt.strip()):
            continue
        meta = [sub.get(o) for o in opts]
        if any(m is None or m[0] is None for m in meta):
            continue
        if not all("Q5" in (m[1] or "").split(",") for m in meta):   # people only
            continue
        best = max(m[0] for m in meta)
        if best <= QRANK_FLOOR:
            out.append((best, qid, prompt, opts))
    out.sort()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    hits = offenders()
    for best, qid, prompt, opts in hits:
        print(f"[{best:>8,}] {qid[:34]:36} {prompt[:44]:46} {', '.join(opts)[:70]}")
    print(f"\n{len(hits)} unanswerable all-people comparisons (floor {QRANK_FLOOR:,})")

    if a.write and hits:
        doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
        # Shape-keyed: writing a flat dict here would wipe every generator's guard.
        bucket = doc.setdefault("corpus", {})
        for _best, qid, prompt, _opts in hits:
            bucket[qid] = "unanswerable: bare comparison, every option an obscure person"
        TOMBSTONES.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {len(hits)} tombstones into the `corpus` bucket")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
