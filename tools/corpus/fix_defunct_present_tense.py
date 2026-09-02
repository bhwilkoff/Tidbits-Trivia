"""Defunct subjects asked in the PRESENT tense, plus one wrong-answer row.

MEASUREMENT FIRST. A naive sweep ("subject has a historical p31") flags 1,123
rows; 97 of those are present-tense; and MOST of the 97 are CORRECT. Canada,
India, New Zealand and Syria all carry `dominion of the British Empire` /
`historical region` p31 codes ALONGSIDE still being countries, and Lower Austria
(`federal state of Austria`), Yorkshire, Alsace and Manchuria are places that
plainly still exist. Present tense is right for every one of them. The generator
is already largely correct here: it produced 345 past-tense capitals, 344
past-tense continents and 222 past-tense languages on its own.

So the discriminator is not the subject alone, it is TEMPLATE x SUBJECT TYPE:

  * `wd:continent:` only needs the subject to be a PLACE. "On which continent is
    Gaul?" / "...is Sumer?" / "...is Manchuria?" all parse and answer cleanly --
    that land is still exactly where it was -- so historical REGIONS keep the
    present tense. Flipping them was a regression this tool made and reverted:
    "On which continent WAS Manchuria?" is simply false. Continent breaks two
    ways only: the subject is a PERIOD or PEOPLE and so is not located anywhere
    ("On which continent is Viking Age?" -> cull), or the subject is a defunct
    POLITY, which is not a piece of land at all ("On which continent is Tang
    dynasty?" -> flip). A polity that is ALSO tagged as a region keeps the
    present tense, because the region reading is the one that survives.

  * `wd:capital:` / `wd:currency:` / `rel:P37:` need a POLITY THAT STILL EXISTS,
    because "what IS the capital" asserts one today. Wallachia is a historical
    region of Romania and has no capital now, so "What is the capital of
    Wallachia?" is wrong in a way "On which continent is Wallachia?" is not.

Two actions follow, and the repair is deliberately the bigger one -- a wrong
tense is a fixable defect, not a reason to destroy a good question:

  A. FLIP TENSE (repair) for a defunct polity/region on a polity template.
     The verb is the only thing that changes. The corpus's own convention for
     these is "What was the capital of Yuan dynasty?" -- no article -- across 30+
     existing rows, so leaving the subject phrase untouched matches what is
     already shipped, and no flip collides with an existing prompt.

  B. CULL where the subject is a PERIOD or a PEOPLE. These do not parse in ANY
     tense: "What currency is used in Aztecs?" and "What is the capital of
     Vandals?" are ungrammatical, and "the capital of Military dictatorship in
     Brazil" / "...of German military administration in occupied France during
     World War II" additionally lead with a repellent framing for a pub round.

  Rule B applies ONLY to the bare generator templates (`wd:`/`rel:`/`fact:` +
  Qid). The first version of this omitted that gate and culled 52 rows, among
  them richly-worded AUTHORED questions (`src:describe:` ids) whose subject is a
  period but whose template asks the RIGHT question about one -- "Spanning
  roughly the 5th to late 15th centuries, this era began with the fall of the
  Western Roman Empire ... Which historical period is this?" A period subject is
  a defect only when the template demands a place; when the template asks "which
  era is this?" it is the whole point of the question.

  D. THE EXPLANATION IS PART OF THE ROW. `wd:continent:` explanations open with a
     GENERATED lead sentence, "<subject> is in <continent>.", and fixing only the
     prompt and the answer index leaves that lead contradicting both. Kazakhstan's
     still read "Kazakhstan is in Europe." after rule C had moved the answer to
     Asia -- the reveal would have argued with itself on screen. Every rule below
     rewrites the lead it invalidates: rule C repoints the continent, rule A
     flips the lead's verb along with the prompt's. Only that generated first
     sentence is touched; the trailing encyclopedia blurb is left alone, because
     "Wallachia ... is situated north of the Lower Danube" is about the region
     and is still true.

  C. ONE-ROW FIX, not a sweep: "On which continent is Kazakhstan?" was answered
     "Europe" with "Asia" sitting right there in the options. About 90% of the
     country is in Asia, so the row marked the better answer wrong. Only this
     row is touched; there is no class here to sweep.
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

# Subject types with no place-reading at all: an era and an ethnic group are not
# somewhere, and do not have a capital or a currency.
PERIOD_OR_PEOPLE = {"Q11514315", "Q4204501", "Q15401633", "Q1197588"}
# ...but these codes also tag things that ARE places/polities (the Shang dynasty
# is tagged `historical period` too), so a subject only counts as period/people
# when it has NO place-or-polity reading.
PLACE_OR_POLITY = {
    "Q1620908", "Q3024240", "Q133156", "Q15661340", "Q28171280", "Q48349",
    "Q50068795", "Q223832", "Q671370", "Q6256", "Q3624078", "Q515", "Q1549591",
    "Q62049", "Q35657", "Q10864048", "Q82794", "Q1520223", "Q7275", "Q417175",
    "Q836688", "Q1414991", "Q846025", "Q19953632", "Q6266", "Q11042", "Q1292119",
}
CURRENT = {"Q6256", "Q3624078", "Q1520223", "Q515", "Q1549591", "Q5119",
           "Q62049", "Q35657", "Q10864048", "Q82794", "Q1637706", "Q200250"}

# Derived from the p31 LABELS rather than hardcoded, so the split is inspectable:
# a POLITY is an organisation that ended, a REGION is ground that did not.
# A subject whose type names a CURRENT administrative unit still exists, however
# many historical codes it also carries. Lower Austria is tagged both `federal
# state of Austria` and `historical region`; it is a live Austrian state with a
# live capital, and "What WAS the capital of Lower Austria?" is false. This is
# the same shape as the Canada/India/New Zealand case in the docstring, one level
# down, and the hardcoded CURRENT set below could not see it.
CURRENT_RX = re.compile(r"federal state|region of|state of|province of|"
                        r"department of|county of|municipality|prefecture of", re.I)
POLITY_RX = re.compile(r"dynasty|state|colony|empire|kingdom|country|dominion|"
                       r"governorate|caliphate|republic|regime|sultanate", re.I)
REGION_RX = re.compile(r"region|city|civilization|archaeological|county|"
                       r"settlement|island|territory", re.I)

POLITY_TMPL = ("wd:capital:", "wd:currency:", "rel:P37:")
# Only the bare generated rows. Authored `src:` questions choose their own
# phrasing and are none of this tool's business -- see the docstring.
GEN = re.compile(r"^(wd|rel|fact):[A-Za-z0-9]+:Q\d+$")
PRESENT = re.compile(r"\bis\b|\bare\b|currency is used")

FLIPS = [
    (re.compile(r"^What is the capital of "), "What was the capital of "),
    (re.compile(r"^What currency is used in "), "What currency was used in "),
    (re.compile(r"^On which continent is "), "On which continent was "),
    (re.compile(r"^On which continent are "), "On which continent were "),
    (re.compile(r"^Which of these is an official language of "),
     "Which of these was an official language of "),
    (re.compile(r"^Which continent is (.*) part of\?$"), None),  # handled below
]

KAZ = "wd:continent:Q232"


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    labels = json.loads(LABELS.read_text())
    pat = re.compile(r"former|historical|defunct|ancient|extinct|abolished|"
                     r"colony|colonial|empire|dissolved|past ", re.I)
    defunct = {k for k, v in labels.items() if pat.search(v)}

    con = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    p31 = {t: set(c for c in (p or "").split(",") if c)
           for t, p in con.execute("select title, p31 from subject")}

    flipped, culled, fixed = [], [], []
    keep = []
    for q in qs:
        qid, prompt = q[0], q[1]

        if qid == KAZ:  # rules C + D
            asia = q[2].index("Asia")
            if q[3] != asia:
                q[3] = asia
                q[6] = re.sub(r"^Kazakhstan is in Europe\.", "Kazakhstan is in Asia.",
                              q[6] or "")
                fixed.append(prompt)
            keep.append(q)
            continue

        if not GEN.match(qid):
            keep.append(q)
            continue

        subj = q[7] if len(q) > 7 else None
        types = p31.get(subj or "", set())
        type_names = [labels.get(c, "") for c in types]
        if (not (types & defunct) or (types & CURRENT)
                or any(CURRENT_RX.search(n) for n in type_names)
                or not PRESENT.search(prompt)):
            keep.append(q)
            continue

        # rule B: a period or a people, with no place-or-polity reading at all
        if (types & PERIOD_OR_PEOPLE) and not (types & PLACE_OR_POLITY):
            culled.append((qid, prompt))
            continue

        # rule A: polity templates assert a present-day fact; flip the verb
        if qid.startswith(POLITY_TMPL) or qid.startswith("wd:continent:"):
            if qid.startswith("wd:continent:"):
                polity = any(POLITY_RX.search(n) for n in type_names)
                region = any(REGION_RX.search(n) for n in type_names)
                # Ground that still exists keeps the present tense.
                if region or not polity:
                    keep.append(q)
                    continue
            new = prompt
            m = re.match(r"^Which continent is (.*) part of\?$", prompt)
            if m:
                new = f"Which continent was {m.group(1)} part of?"
            else:
                for rx, repl in FLIPS:
                    if repl and rx.match(prompt):
                        new = rx.sub(repl, prompt)
                        break
            if new != prompt:
                q[1] = new
                # rule D: the generated lead sentence must move with the prompt.
                if qid.startswith("wd:continent:") and q[6]:
                    q[6] = re.sub(r"^(" + re.escape(subj) + r") is in ",
                                  r"\1 was in ", q[6])
                flipped.append((prompt, new))
        keep.append(q)

    print(f"flipped to past tense: {len(flipped)}")
    for a, b in flipped:
        print(f"    {a}\n      -> {b}")
    print(f"\nculled (period/people): {len(culled)}")
    for qid, p in culled:
        print(f"    {p}")
    print(f"\none-row answer fix: {len(fixed)}")
    for p in fixed:
        print(f"    {p} -> Asia")

    if not (flipped or culled or fixed):
        print("nothing to do")
        return

    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, p in culled:
        tomb[qid] = "subject is a historical period or people: no capital, currency or continent"
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}")


if __name__ == "__main__":
    main()
