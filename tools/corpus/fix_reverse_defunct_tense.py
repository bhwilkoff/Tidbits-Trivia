"""The REVERSE templates ask about vanished countries in the present tense.

`fix_defunct_present_tense.py` swept the forward templates -- "What is the
capital of X?" -- and flipped the ones whose SUBJECT had ended. The `rev:*`
family asks the same facts backwards, so the polity is the ANSWER, not the
subject, and the sweep never looked at it:

    Of which country is Saint Petersburg the capital?  -> Russian Empire
    Which country uses the Reichsmark as its official currency?  -> Nazi Germany
    Of which country is Winchester the capital?  -> Kingdom of England

Every one asserts a present-day fact about something that ended, and the first
of those is wrong twice over: Saint Petersburg is not a capital of anything now.

WHY THE FORWARD SWEEP COULD NOT HAVE CAUGHT THESE, and a flaw it shared: that
tool skipped any subject carrying a "current" p31 code, and `sovereign state`
(Q3624078) was in that set. But Wikidata tags historical states as sovereign
states too -- Great Moravia is `historical country` AND `sovereign state` -- so
the check excluded exactly the rows it was hunting. The fix is to treat
`historical country` (Q3024240) as DECISIVE: whatever else a subject is tagged,
that code means it ended. Re-running the forward sweep under the decisive rule
finds 0 further rows, so the shipped forward repair was complete; the blind spot
cost nothing there and everything here.

Three prompt shapes, 72 rows, verb-only flips:
    "Which country uses the X ..."        -> "Which country used the X ..."
    "Of which country is X the capital?"  -> "Of which country was X the capital?"
    "Of which country is X an official language?" -> "... was X ..."

The answers stay. These are good questions with the wrong tense -- a flip keeps
72 pieces of real history that a cull would have thrown away.
"""
import json
import re
import sqlite3
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

# Decisive: this code means the thing ended, whatever else it is also tagged.
STRONG_DEFUNCT = {"Q3024240"}
PRESENT = re.compile(r"\bis\b|\bare\b|\buses\b")

FLIPS = [
    (re.compile(r"^Which country uses the "), "Which country used the "),
    (re.compile(r"^Of which country is "), "Of which country was "),
    (re.compile(r"^Which of these is an official language of "),
     "Which of these was an official language of "),
]


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p31 = {t: set(c for c in (p or "").split(",") if c)
           for t, p in con.execute("select title, p31 from subject")}

    flipped = []
    for q in qs:
        if not q[0].startswith("rev:"):
            continue
        ans = q[2][q[3]]
        if not (p31.get(ans, set()) & STRONG_DEFUNCT) or not PRESENT.search(q[1]):
            continue
        for rx, repl in FLIPS:
            if rx.match(q[1]):
                new = rx.sub(repl, q[1])
                if new != q[1]:
                    flipped.append((q[1], new))
                    q[1] = new
                break

    print(f"flipped: {len(flipped)}")
    for a, b in flipped:
        print(f"    {a}\n      -> {b}")
    if not flipped:
        print("nothing to do")
        return

    doc["count"] = len(qs)
    doc["version"] = md5(json.dumps(
        qs, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} rows kept   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
