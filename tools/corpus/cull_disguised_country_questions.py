"""Questions that only PRETEND to be about their subject.

Owner steer, 2026-09-02: "We don't need ambiguity and we are not trying to create
'gotcha' questions... they should all be of high quality and not have dubious
answers that feel false even if they are technically right." This REVERSES the
rule these sweeps had been run under ("a weak question is not a wrong one"), so
rows previously left in scope are now in scope for removal.

The clearest measurable form of "technically right but feels false" in this
corpus: a national fact asked of a CITY or a SUBDIVISION, where the answer is
simply the country's own answer.

    Which of these is an official language of Paris?   -> French
    Which of these is an official language of Naples?  -> Italian
    What currency is used in Tbilisi?                  -> Georgian lari

Paris does not have an official language; France does. The player is really
being asked "which country is Paris in?" wearing a costume, and the premise --
that a city declares a language -- is false. That is the disqualifying part, not
the difficulty.

THE SAME TEMPLATE IS GENUINELY GOOD when the answer DIFFERS from the country's,
because then the fact is real and worth knowing:

    Which of these is an official language of Bengaluru?  -> Kannada   (India)
    Which of these is an official language of Goa?        -> Konkani   (India)
    What currency is used in Hong Kong?  -> Hong Kong dollar  (China)
    What currency is used in Gibraltar?  -> Gibraltar pound   (UK)

So the discriminator is derived, not guessed: compare each sub-national row's
answer against what THIS CORPUS says the parent country's answer is (P17 from the
relation table -> the country's own `wd:currency:` / `rel:P37:` row). Equal means
disguised; different means a real regional fact. The 29 rows that differ are kept
and are some of the better geography questions in the set.

Two guards, both of which changed the outcome:

  * A SUBJECT THAT IS ITSELF A COUNTRY IS NOT SUB-NATIONAL. Vatican City, Monaco
    and Singapore were flagged only because their P17 country is themselves, and
    "What currency is used in Vatican City?" is a perfectly fair question. Any
    subject tagged country/sovereign state is excluded outright.

  * COUNTRY NAMES ARE NOT KEYS. The corpus writes "the United States" and the
    relation table writes "United States", so Little Rock had no national row to
    compare against and would have been silently KEPT. Names are normalised
    before comparing.

A THIRD source and a THIRD guard, both added after reading the first run's KEPT
lists rather than just its cull list:

  * THE CORPUS IS NOT THE ONLY PLACE THE NATIONAL ANSWER LIVES. Grand Rapids and
    Duesseldorf landed in "unverifiable" because their countries have no
    `rel:P37:` row to compare against -- the United States one was culled earlier
    this session, since there is no federal official language. The relation table
    carries P37/P38 per country directly, so it is consulted as a fallback and
    resolves them.

  * A HISTORICAL P17 IS NOT A PARENT COUNTRY. London's P17 is "Roman Empire" and
    Yakutsk's is "Tsardom of Russia", so comparing against those countries found
    "no match" and filed two plainly disguised rows ("official language of London
    -> English") under GENUINELY INTERESTING. A country that no longer exists
    cannot be the country a city is in today, so those comparisons are rejected
    and the row falls through to the unverifiable-and-kept path unless the
    fallback resolves it.

Anything still unresolved after every guard is KEPT, never culled: a row this
tool cannot verify is not a row it gets to delete.
"""
import json
import re
import sqlite3
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
LABELS = ROOT / "tools" / "corpus" / "p31_labels.json"

SUB = re.compile(r"\b(city|town|village|municipality|county seat|big city|"
                 r"human settlement|borough|state of|province of|federal state|"
                 r"region of|prefecture|district)\b", re.I)
IS_COUNTRY = re.compile(r"\b(country|sovereign state|city-state|microstate)\b", re.I)


def norm(s):
    return re.sub(r"^the ", "", (s or "").strip(), flags=re.I).lower()


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    labels = json.loads(LABELS.read_text())
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    title2qid = {t: q for q, t in con.execute("select qid, title from subject")}
    p31 = {t: set(c for c in (p or "").split(",") if c)
           for t, p in con.execute("select title, p31 from subject")}
    country = {}
    for q, tl in con.execute("select qid, target_label from relation where prop='P17'"):
        country.setdefault(q, tl)
    # Fallback source: what the relation table itself says a COUNTRY's official
    # language / currency is, keyed by the country's own title.
    rel_nat = {"P37": {}, "currency": {}}
    qid2title = {q: t for q, t in con.execute("select qid, title from subject")}
    for prop, key in (("P37", "P37"), ("P38", "currency")):
        for q, tl in con.execute("select qid, target_label from relation where prop=?", (prop,)):
            t = qid2title.get(q)
            if t:
                rel_nat[key].setdefault(norm(t), set()).add(tl)
    # A country that ended is not the country a city is in NOW.
    defunct_titles = {t for t, p in con.execute("select title, p31 from subject")
                      if "Q3024240" in (p or "")}

    nat = {"P37": {}, "currency": {}}
    for q in qs:
        m = re.match(r"^Which of these (?:is|was) an official language of (.*)\?$", q[1])
        if m:
            nat["P37"].setdefault(norm(m.group(1)), set()).add(q[2][q[3]])
        m = re.match(r"^What currency (?:is|was) used in (.*)\?$", q[1])
        if m:
            nat["currency"].setdefault(norm(m.group(1)), set()).add(q[2][q[3]])

    cull, kept_interesting, unresolved = [], [], []
    for q in qs:
        s = q[7] if len(q) > 7 else None
        if not s:
            continue
        tmpl = q[0].split(":")[1] if ":" in q[0] else ""
        if tmpl not in ("P37", "currency"):
            continue
        names = [labels.get(c, c) for c in p31.get(s, set())]
        if not names or not any(SUB.search(n) for n in names):
            continue
        if any(IS_COUNTRY.search(n) for n in names):   # guard 1
            continue
        c = country.get(title2qid.get(s, ""))
        if c in defunct_titles:                        # guard 3
            unresolved.append((q, f"{c} (historical - not a parent)"))
            continue
        want = set()
        if c:
            want |= nat[tmpl].get(norm(c), set())      # guard 2
            want |= rel_nat[tmpl].get(norm(c), set())  # fallback source
        if not want:
            unresolved.append((q, c))
            continue
        (cull if q[2][q[3]] in want else kept_interesting).append((q, c))

    print(f"DISGUISED -> cull: {len(cull)}")
    for q, c in cull:
        print(f"    {q[1][:58]:60} -> {q[2][q[3]]:20} ({c})")
    print(f"\nreal regional fact -> KEPT: {len(kept_interesting)}")
    for q, c in kept_interesting[:8]:
        print(f"    {q[1][:58]:60} -> {q[2][q[3]]:20} ({c})")
    print(f"\nunverifiable -> KEPT: {len(unresolved)}")
    for q, c in unresolved[:8]:
        print(f"    {q[1][:58]:60} -> {q[2][q[3]]:20} ({c})")

    if not cull:
        print("\nnothing to do")
        return
    ids = {q[0] for q, _ in cull}
    keep = [q for q in qs if q[0] not in ids]
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for q, c in cull:
        tomb[q[0]] = (f"disguised 'which country is this in?': a sub-national subject "
                      f"answered with {c}'s own national answer")
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
