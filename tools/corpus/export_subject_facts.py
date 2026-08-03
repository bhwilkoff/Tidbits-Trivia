"""Give the gate its facts in CI, where the 150 MB source database does not exist.

Two gate rules read `corpus_source.sqlite`: PRESENT-TENSE-PAST needs to know which
subjects are historical states (Wikidata Q3024240, so "What currency is used in
the Kingdom of Navarre?" is caught), and FAME-TELL needs QRank to know that
Jonathan Kuminga is three orders of magnitude more obscure than Michael Jordan.

That database is a 150 MB build artifact and is gitignored, so on a CI checkout
both rules silently saw nothing. They did not error — they FAILED OPEN, reporting
0 found and passing. FAME-TELL shipped on 2026-08-02 protecting nothing at all in
the only place the check actually runs, and PRESENT-TENSE-PAST had been that way
longer; the gate self-test named it (`BLIND RULES: ['PRESENT-TENSE-PAST']`) the
first time it ran in CI, which is the entire reason that test exists.

This exports just the facts the gate reads, for just the strings the corpus
actually uses as an option or a subject — 39,862 QRanks and 403 historical titles,
about 1 MB, versus 150 MB of source data:

    python3 tools/corpus/export_subject_facts.py

`resync_corpus.sh` runs it, so the file tracks the corpus. The gate prefers the
database when it is present (a local run gets the freshest data) and falls back to
this file, and fails loudly when it has neither rather than passing blind.
"""
import json
import pathlib
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SOURCE_DB = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
OUT = ROOT / "tools" / "corpus" / "subject_facts.json"

HISTORICAL_STATE = "Q3024240"


def main():
    if not SOURCE_DB.exists():
        print(f"no {SOURCE_DB.name} — nothing to export (this is the machine that "
              f"builds the corpus, so it should be here)")
        return 1

    rows = json.loads(CORPUS.read_text())["questions"]
    used = set()
    for r in rows:
        if isinstance(r[2], list):
            used.update(str(o) for o in r[2])
        if r[7]:
            used.add(str(r[7]))

    db = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    qrank = {t: q for t, q in db.execute(
        "select title, qrank from subject where qrank is not null")
        if q and t in used}
    historical, p31 = [], {}
    for t, p in db.execute("select title, p31 from subject"):
        if not p:
            continue
        if HISTORICAL_STATE in p:
            historical.append(t)
        if t in used:
            p31[t] = p.split(",")[0]
    db.close()

    # p31 too: ODD-ONE-KIND reads the Wikidata TYPE through type_family() to see
    # a city among three countries, and it shipped blind in CI for exactly one
    # commit because that lookup lived only in the database. Same mistake as
    # FAME-TELL, caught the same way — by the self-test, in CI.
    OUT.write_text(json.dumps({"qrank": qrank, "historical": sorted(historical),
                               "p31": p31},
                              ensure_ascii=False, separators=(",", ":"),
                              sort_keys=True))
    print(f"wrote {OUT.relative_to(ROOT)}: {len(qrank):,} qranks, "
          f"{len(p31):,} types, {len(historical):,} historical titles, "
          f"{OUT.stat().st_size / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
