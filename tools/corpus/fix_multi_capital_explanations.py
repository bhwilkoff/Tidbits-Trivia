"""Name the OTHER capital, for the countries that have more than one.

    Q: What is the capital of South Africa?      A: Pretoria
    explanation: "South Africa → Pretoria. South Africa, officially the Republic
                  of South Africa, is the southernmost country in Africa."

A team answers Cape Town. They are not wrong — Cape Town is South Africa's
LEGISLATIVE capital, Pretoria the executive one, Bloemfontein the judicial. The
host reads the explanation out to settle it and finds it says nothing about any
of that, because the generator only ever wrote "subject → answer" plus the
article's opening line.

The answer is right in every one of these rows, so this is not a cull. The
EXPLANATION is the payoff and the arbiter, and on precisely the questions a pub
argues about it was silent. Ten rows, all constitutional/official answers:
South Africa, Bolivia, Eswatini, Sri Lanka, Malaysia, Tanzania, Benin, Ivory
Coast, Chile, Myanmar.

A committed fix_* script rather than a hand edit, because a regeneration would
otherwise drop it — the failure mode Decision 051 was written for.

    python3 tools/corpus/fix_multi_capital_explanations.py           # report
    python3 tools/corpus/fix_multi_capital_explanations.py --write
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS_JSON = ROOT / "assets/corpus.json"

# subject -> the sentence a host needs to settle the room.
DISAMBIGUATION = {
    "South Africa": "Pretoria is the executive capital; Cape Town is the legislative capital and Bloemfontein the judicial one.",
    "Bolivia": "Sucre is the constitutional capital; La Paz is the seat of government.",
    "Eswatini": "Lobamba is the legislative and royal capital; Mbabane is the administrative one.",
    "Sri Lanka": "Sri Jayawardenepura Kotte is the legislative capital; Colombo is the commercial capital and largest city.",
    "Malaysia": "Kuala Lumpur is the official capital; Putrajaya is the administrative centre.",
    "Tanzania": "Dodoma has been the official capital since 1974; Dar es Salaam is the largest city and commercial centre.",
    "Benin": "Porto-Novo is the official capital; Cotonou is the seat of government.",
    "Ivory Coast": "Yamoussoukro is the official capital; Abidjan is the seat of government and largest city.",
    "Chile": "Santiago is the capital; the National Congress sits in Valparaíso.",
    "Myanmar": "Naypyidaw has been the capital since 2005; Yangon was the former capital and is still the largest city.",
}

STEM = "What is the capital of "


def rows_to_fix(rows):
    out = []
    for r in rows:
        prompt = r[1]
        if not prompt.startswith(STEM):
            continue
        subject = prompt[len(STEM):].rstrip("?").strip()
        note = DISAMBIGUATION.get(subject)
        if not note:
            continue
        expl = r[6] or ""
        if note in expl:
            continue                      # already carries it — idempotent
        out.append((r, subject, note))
    return out


def patch(expl: str, note: str) -> str:
    """Put the disambiguation straight after the "X → Y." lead, where a host
    reading aloud reaches it immediately, not buried behind the article blurb."""
    m = re.match(r"^([^.]*→[^.]*\.)\s*(.*)$", expl, re.S)
    if m:
        return f"{m.group(1)} {note} {m.group(2)}".strip()
    return f"{note} {expl}".strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    doc = json.loads(CORPUS_JSON.read_text())
    todo = rows_to_fix(doc["questions"])
    for r, subject, note in todo:
        print(f"{subject:14} {r[0]}")
        print(f"   + {note}")
    print(f"\n{len(todo)} multi-capital explanation(s) to enrich")

    if a.write and todo:
        for r, _subject, note in todo:
            r[6] = patch(r[6] or "", note)
        # RECOMPUTE the content hash. Writing new content under the old version is
        # the exact failure 29 fix_*.py tools shipped — the web client busts its
        # IndexedDB cache on this string, so every returning player would keep the
        # explanations we just corrected. Byte-identical to export_json.py.
        body = json.dumps(doc["questions"], ensure_ascii=False, separators=(",", ":"))
        version = hashlib.md5(body.encode()).hexdigest()[:12]
        CORPUS_JSON.write_text(
            f'{{"version":"{version}","count":{len(doc["questions"])},"questions":{body}}}')
        print(f"wrote assets/corpus.json (version {version})")
        print("now run: tools/corpus/resync_corpus.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
