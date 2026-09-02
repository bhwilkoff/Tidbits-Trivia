"""AUDIT ONLY — DO NOT APPLY. Population superlatives whose answer is stale.

This tool REPORTS and deliberately does not write. See "why this does not ship".

The `fact` table's P1082 is not merely corrupt in places -- it is SYSTEMATICALLY
stale. The United States is stored at 3,929,214, which is the 1790 census.
Canada is stored at 44. France sits at 40,681,000 against a lead saying 69.1
million, Egypt at 28M against 107M, Russia at 101M against 140M. Of the countries
where both sources give a figure, 93 disagree by 2x or more.

No internal check can see this -- the questions were generated from that same
table, so the corpus agrees with it perfectly (`sup:*` reported 0 wrong answers
over 8,777 rows). The Wikipedia `prose` lead is an INDEPENDENT source, and
against it 481 of the 3,117 population superlatives turn out to name the wrong
answer:

    Which of these is the most populous?
      Buenos Aires (3.1M) / Malacca City / Cape Town / Abu Dhabi (2.5M)
      -> marked Abu Dhabi

    Which of these four has the most people?
      Oregon / Pennsylvania (13M) / New Jersey / Minnesota (5.3M)
      -> marked Minnesota

THE OPTIONS ARE FINE; ONLY THE ANSWER INDEX IS WRONG. So this repoints the index
rather than rewriting option sets or deleting rows -- 481 questions repaired,
none lost, which matters while the corpus is being grown back toward 100K.

STRICTNESS, because a half-corrected comparison is worse than an uncorrected one:
a row is only touched when EVERY option has an independently verified figure. If
one option's population can be checked against its lead and another's cannot, the
unverifiable one may still be a stale census value, and correcting only its rival
would hand the answer to whichever option happened to have prose. Those rows are
left exactly as they are and reported, not guessed at.

CITIES ARE EXCLUDED ENTIRELY, and that exclusion was learned the hard way here.
A city's lead routinely quotes the METRO area while the fact table stores the
city proper, so "correcting" one against the other is not a correction at all.
The first run of this repointed 227 answers and its own output showed the damage:
Venice was promoted to 2,600,000 (the metropolitan city; Venice proper is about
250,000) over Genoa's 580,097, turning a RIGHT answer into a wrong one, and
Indianapolis (metro 2.6M) was promoted over San Diego (city 1.35M) the same way.
The city/metro ambiguity is exactly the false positive already identified for
Atlanta one commit earlier, and it had not been carried across.

Countries and subdivisions have no such ambiguity -- a state or a nation has one
population -- so the repair is confined to them. Cities keep whatever the fact
table says; their errors need a source that distinguishes city from metro, which
this tool does not have.

A tie under corrected data is also left alone: two options within 2% of each
other cannot be separated by figures this approximate ("over 41 million").

WHY THIS DOES NOT SHIP, after four rounds of tightening. The finding is real: 481
of 3,117 population superlatives name the wrong answer against the leads. But the
extractor takes the FIRST population-ish figure in a lead, and that figure is
frequently about something else entirely:

    Indiana   -> 2,000,000   the lead sentence is about INDIANAPOLIS's metro area
    Australia -> 5,000,000   the lead actually says "almost 29 million"
    England   -> 15,000,000  the lead actually says "the population was 56,490,048"

Indiana (6.9M) really does beat Louisiana (4.6M), so applying that "correction"
would have turned a RIGHT answer wrong -- the exact failure this pass exists to
remove. Each tightening round removed one class of error and revealed another:
cities quoting metro figures, then a 1.5x threshold correcting one side of a
comparison and not the other, then continents, then simply the wrong sentence.

A regex over prose cannot carry this. THE REAL FIX IS A DATA REFRESH -- re-fetch
P1082 from Wikidata into `corpus_source.sqlite` and regenerate -- which repairs
every affected question at the source instead of guessing at the answer index.
Until then these rows stay as they are: knowingly stale, but not made worse.
"""
import json
import importlib.util
import re
import sqlite3
from hashlib import md5
from pathlib import Path

CITY_RX = re.compile(r"\bcity\b|\btown\b|municipality|human settlement|big city|"
                     r"county seat|borough|capital city", re.I)
# Only these. A CONTINENT is not a country: "Americas" parsed out of its lead as
# 10,000,000 (it holds about a billion people) and would have promoted Europe
# over it -- a bad parse turning a right answer wrong. Restricting to entities
# that have exactly one official population number keeps the extractor honest.
ELIGIBLE_RX = re.compile(r"\bcountry\b|sovereign state|\bstate of\b|province of|"
                         r"federal state|\bU\.S\. state\b|region of|"
                         r"constituent country|island country", re.I)

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"
SRC = ROOT / "tools" / "corpus" / "corpus_source.sqlite"

# When the lead states a figure it is simply the better source, and it is used
# UNCONDITIONALLY. An earlier version only substituted at a 1.5x discrepancy,
# which quietly created the very asymmetry this tool exists to avoid: Colombia
# was corrected to 52M while Italy, only 1.17x stale, kept a stored 50.2M and
# LOST -- though Italy has about 59 million people. Correcting one side of a
# comparison and not the other is how a repair invents a new wrong answer.
TIE = 0.02       # within 2% is a tie these approximate figures cannot break
MIN_WORDS = ("smallest", "fewest", "least", "lowest", "tiniest")


def load_extractor():
    spec = importlib.util.spec_from_file_location(
        "acp", str(ROOT / "tools/corpus/audit_corrupt_place_facts.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.prose_population


def main():
    prose_population = load_extractor()
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    q2t = {q: t for q, t in con.execute("select qid, title from subject")}
    fact = {}
    for qid, prop, v in con.execute(
            "select qid, prop, value from fact where kind='num' and prop='P1082'"):
        t = q2t.get(qid)
        if t and v is not None:
            fact.setdefault(t, float(v))
    lead = {q2t.get(q): l for q, l in con.execute("select qid, lead from prose")
            if q2t.get(q)}
    labels = json.loads((ROOT / "tools/corpus/p31_labels.json").read_text())
    p31 = {t: set(c for c in (pp or "").split(",") if c)
           for t, pp in con.execute("select title, p31 from subject")}

    def types_of(t):
        return " ".join(labels.get(c, c) for c in p31.get(t, set()))

    def eligible(t):
        n = types_of(t)
        return bool(ELIGIBLE_RX.search(n)) and not CITY_RX.search(n)

    # A figure is TRUSTED only when the lead confirms or corrects it.
    trusted = {}
    for t, v in fact.items():
        if not eligible(t):     # countries and subdivisions only; see the docstring
            continue
        pv = prose_population(lead.get(t))
        if not pv or v <= 0:
            continue
        trusted[t] = pv

    fixed, unverifiable, tied = [], 0, 0
    for q in qs:
        if not q[0].startswith("sup:P1082"):
            continue
        vals = [trusted.get(o) for o in q[2]]
        if any(v is None for v in vals):
            unverifiable += 1
            continue
        want_min = any(w in q[1].lower() for w in MIN_WORDS)
        best = min(range(4), key=lambda i: vals[i]) if want_min \
            else max(range(4), key=lambda i: vals[i])
        runner = sorted(vals, reverse=not want_min)[1]
        if runner and abs(vals[best] - runner) / max(vals[best], 1) < TIE:
            tied += 1
            continue
        if vals[best] != vals[q[3]]:
            fixed.append((q[1], q[2][q[3]], q[2][best],
                          vals[q[3]], vals[best]))
            q[3] = best

    print(f"answers repointed: {len(fixed)}")
    for p, was, now, wv, nv in fixed[:12]:
        print(f"    {p[:42]:44} {was} ({wv:,.0f})  ->  {now} ({nv:,.0f})")
    print(f"\nleft alone -- not every option independently verifiable: {unverifiable}")
    print(f"left alone -- corrected values tie: {tied}")
    print("\nAUDIT ONLY: nothing written. The prose extractor is not reliable enough")
    print("to rewrite an answer index -- see the docstring. Fix P1082 at the source.")


if __name__ == "__main__":
    main()
