"""CLUE-CROSSED, the wide detector: one prose clue attached to two different subjects.

The narrow 2026-08-30 pass caught 16 rows by a hand-written "person clue, work
answer" shape. The real class is far bigger and needs no shape at all: the
`src:cloze` / `src:describe` generator wrote the SAME prompt onto two different
articles, so one of the pair is answerable and the other is nonsense.

    "Breaking from its series' Greek mythology roots, this 2018 action-adventure
     game relocates its story to Norse mythology's realm of Midgard."
       -> God of War (2018 video game)   [correct]
       -> House of Bonaparte             [garbage; it was on the Mac cockpit's
                                          first question of a cold host run]

Detection is exact and needs no judgment: an identical prompt string on two
different `source_title`s. The only judgment is WHICH of the pair is wrong, and
that is decided by how much of the prompt's vocabulary appears in each subject's
own Wikipedia lead. A correct clue is written from the lead, so its overlap is
high; a crossed one shares almost nothing.

Rows whose winner cannot be decided confidently are reported, never auto-fixed
(`detector-that-fires-on-quality`: read the hits before any bulk change).

    python3 tools/corpus/audit_clue_crossed.py                # report only
    python3 tools/corpus/audit_clue_crossed.py --write        # tombstone the losers
"""
import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "TidbitsTrivia/Resources/corpus.sqlite"
SOURCE = ROOT / "tools/corpus/corpus_source.sqlite"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"

# Words that carry no discriminating signal — they appear in every clue.
STOP = set("""a an and are as at be been but by for from had has have he her his in
into is it its of on or she that the their them they this to was were which who
whose with you your one two three four first second new than then there these those
after before during over under between about most more many some such other another
what where when how why also not no all both each much own same so too very can
will just don should now""".split())

WORD = re.compile(r"[A-Za-z][A-Za-z'-]+")


def content_words(text: str) -> set[str]:
    return {w.lower() for w in WORD.findall(text or "") if len(w) > 2 and w.lower() not in STOP}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="tombstone the losing rows")
    ap.add_argument("--limit", type=int, default=25, help="how many hits to print")
    ap.add_argument("--margin", type=float, default=0.10,
                    help="minimum overlap gap between winner and loser to act")
    a = ap.parse_args()

    if not CORPUS.exists():
        print(f"missing corpus: {CORPUS}", file=sys.stderr)
        return 2
    db = sqlite3.connect(CORPUS)
    src = sqlite3.connect(SOURCE)
    lead = {t: (l or "") + " " + (d or "")
            for t, l, d in src.execute("select title, lead, description from prose")}

    rows = db.execute("""select id, prompt, source_title, template_id, category_id
                         from questions where template_id = 'src'""").fetchall()
    by_prompt: dict[str, list] = defaultdict(list)
    for r in rows:
        by_prompt[r[1]].append(r)

    crossed = {p: v for p, v in by_prompt.items() if len({x[2] for x in v}) > 1}

    decided, undecided = [], []
    for prompt, group in sorted(crossed.items()):
        pw = content_words(prompt)
        if not pw:
            undecided.append((prompt, group, {}))
            continue
        scores = {}
        for r in group:
            body = lead.get(r[2], "")
            # The title itself counts: "God of War" is in the clue's vocabulary.
            sw = content_words(body) | content_words(r[2])
            scores[r[0]] = len(pw & sw) / len(pw)
        ranked = sorted(scores.items(), key=lambda kv: -kv[1])
        if len(ranked) > 1 and ranked[0][1] - ranked[1][1] >= a.margin:
            winner = ranked[0][0]
            for qid, sc in ranked[1:]:
                decided.append((qid, prompt, dict(scores), winner))
        else:
            undecided.append((prompt, group, scores))

    print(f"src rows:                         {len(rows):,}")
    print(f"prompts on more than one subject: {len(crossed):,}")
    print(f"  -> losers decided by lead overlap: {len(decided):,}")
    print(f"  -> pairs too close to call:        {len(undecided):,}")
    print()
    by_title = {r[0]: r[2] for r in rows}
    for qid, prompt, scores, winner in decided[: a.limit]:
        print(f"  DROP {qid}")
        print(f"       {prompt[:110]}")
        print(f"       loser  {by_title[qid]!r} overlap {scores[qid]:.2f}")
        print(f"       keeper {by_title[winner]!r} overlap {scores[winner]:.2f}")
    if undecided:
        print(f"\n  UNDECIDED (read these by hand):")
        for prompt, group, scores in undecided[:10]:
            print(f"    {prompt[:100]}")
            for r in group:
                print(f"       {r[2]!r} overlap {scores.get(r[0], 0):.2f}")

    if a.write:
        # tombstones.json is keyed by SHAPE ({"corpus": {...}, "match": {...}}) and
        # `genguard` reads it that way; a flat write at the top level silently
        # corrupts every shape's guard.
        doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
        tomb = doc.setdefault("corpus", {})
        reason = ("CLUE-CROSSED: this prose clue was generated from a DIFFERENT article "
                  "and pasted onto this subject — unanswerable")
        added = 0
        for qid, *_ in decided:
            if qid not in tomb:
                tomb[qid] = reason
                added += 1
        doc["corpus"] = tomb
        TOMBSTONES.write_text(json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        print(f"\ntombstoned {added:,} new rows -> {TOMBSTONES.relative_to(ROOT)}")
        print("re-run the corpus build so the tombstones take effect in every mirror.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
