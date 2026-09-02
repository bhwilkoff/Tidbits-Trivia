"""Pick the FAMOUS subjects the corpus does not cover, for authoring.

The owner wants the corpus back above 100K while weak rows are being culled, so
growth has to come from subjects that are worth a question in the first place --
not from grinding deeper into obscurity, which is what produced the dry padding
an earlier steer already stopped.

The headroom is real and it is at the TOP of the fame distribution: 330 subjects
at qrank >= 5M and ~7,000 at 1M-5M have ZERO questions, and 7,293 of those carry
a Wikipedia lead in the `prose` table to author from. Uncovered subjects include
YouTube, Wikipedia, ChatGPT, the Titanic, FC Barcelona, the periodic table and
Artificial intelligence -- all better trivia than anything being culled.

EXCLUSIONS are part of the job, not an afterthought. The same brief that asks for
the best corpus rules out topics that make people stop playing, and the raw
fame-ranked list is full of them: pornography sites, sexual anatomy, active
armed conflicts and their factions, terrorist organisations, mass-casualty
events, and Wikipedia list-articles ("Deaths in 2023") that are not subjects at
all. Those are filtered here rather than left for the author to notice.

Usage:  python3 tools/corpus/build_coverage_batch.py [--limit N] [--min-qrank N]
Writes a JSON batch of {qid, title, qrank, lead, description} to stdout.
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

# Topics that would make a pub table put the sheet down.
BLOCK = re.compile(
    r"porn|xnxx|xvideos|onlyfans|sex|sexual|genital|penis|vagina|breast|nude|"
    r"rape|incest|abuse|massacre|genocide|terror|jihad|hamas|hezbollah|isis|"
    r"islamic state|al-qaeda|taliban|shooting|bombing|assassination|suicide|"
    r"holocaust|slavery|lynching|torture|execution|cartel|narco|"
    r"conflict|war crime|invasion of|occupation of|insurgency|militia", re.I)
# Not subjects: Wikipedia housekeeping and list pages.
NOT_A_SUBJECT = re.compile(
    r"^(deaths in|list of|index of|outline of|timeline of|glossary of|"
    r"history of|category:|template:|portal:|wikipedia:)", re.I)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=60)
    ap.add_argument("--min-qrank", type=int, default=1_000_000)
    a = ap.parse_args()

    have = {q[7] for q in json.loads(CORPUS.read_text())["questions"]
            if len(q) > 7 and q[7]}
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    prose = {q: (lead, desc) for q, lead, desc
             in con.execute("select qid, lead, description from prose")}

    out = []
    rows = con.execute("select qid, title, qrank, keep from subject")
    cand = []
    for qid, title, qrank, keep in rows:
        if keep in (0, "0"):
            continue
        try:
            qr = int(qrank or 0)
        except (TypeError, ValueError):
            qr = 0
        if qr < a.min_qrank or title in have:
            continue
        if BLOCK.search(title) or NOT_A_SUBJECT.search(title):
            continue
        if qid not in prose or not (prose[qid][0] or "").strip():
            continue
        cand.append((qr, qid, title))
    cand.sort(reverse=True)
    for qr, qid, title in cand[:a.limit]:
        lead, desc = prose[qid]
        if BLOCK.search(lead or ""):
            continue
        out.append({"qid": qid, "title": title, "qrank": qr,
                    "lead": (lead or "").strip()[:900],
                    "description": (desc or "").strip()})
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
