"""Stale, mis-typed, repellent and ambiguous answers in the currency template.

Found by READING all 258 country/currency pairs rather than diffing corpus
fields against each other -- the two generated rows for a country both come from
the same Wikidata P38 claim, so when the claim is stale they agree with each
other and no cross-check can see it.

CULLED (4) -- no repair exists, because the question itself is the problem:
  * Islamic State -> "Islamic State Dinar". A pub round does not need it.
  * Sahrawi Arab Democratic Republic -> "Sahrawi peseta", a commemorative issue
    that does not circulate; the territory actually uses the Algerian dinar and
    Moroccan dirham. Technically sourced, feels false.
  * Ming dynasty -> "bimetallism", which is a monetary SYSTEM, not a currency:
    the answer is not the kind of thing the question asks for.
  * Zimbabwe -> "United States dollar". Zimbabwe runs a multi-currency regime and
    introduced the ZiG in 2024, so there is no single right answer to repair TO.
    Ambiguity is the disqualifier, not difficulty.

THE REPELLENT STRING WAS ALSO A DISTRACTOR, which culling one row would not have
fixed: "Islamic State Dinar" sat in the option sets of four otherwise innocent
questions -- Vanuatu, Aruba, Albania and the United Kingdom. Removing bad content
means removing it from every option list, not just from the row it is the answer
to. Each is swapped for a neutral currency not already in that set.

REPAIRED (5) -- the fact is right, the string is stale or malformed:
  * "bir" -> "birr" (Ethiopia and the Ethiopian Empire)
  * "Vanuatu vatus" -> "vatu": the unit is singular, and the plural read as a typo
  * "Nuevo sol" -> "sol": renamed in December 2015
  * "Tix" -> "Robux": Roblox retired Tix in 2016

TENSE-FLIPPED (7) -- defunct subjects still asked in the present, missed by the
earlier sweeps because these subjects are not tagged `historical country`:
Classical Athens, Congress Poland, the Paris Commune, the Pahlavi dynasty, East
Pakistan, the Province of North Carolina and the Qing dynasty.

Every rename rewrites the row's generated explanation lead too, so the reveal
does not go on naming the old string.
"""
import json
import re
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

CULL = {
    "wd:currency:Q2429253": "repellent subject for a pub round",
    "wd:currency:Q40362": "the Sahrawi peseta does not circulate; technically sourced but false in practice",
    "wd:currency:Q9903": "'bimetallism' is a monetary system, not a currency: wrong kind of answer",
    "wd:currency:Q954": "Zimbabwe's multi-currency regime has no single correct answer",
}
BANNED_OPTION = "Islamic State Dinar"
SWAP_POOL = ["Chilean peso", "Icelandic krona", "Nepalese rupee", "Ghanaian cedi",
             "Fijian dollar", "Moldovan leu", "Bolivian boliviano"]
RENAME = {                       # id -> (old answer, new answer)
    "wd:currency:Q115": ("bir", "birr"),
    "wd:currency:Q207521": ("bir", "birr"),
    "wd:currency:Q686": ("Vanuatu vatus", "vatu"),
    "wd:currency:Q419": ("Nuevo sol", "sol"),
    "wd:currency:Q692989": ("Tix", "Robux"),
}
# A RENAME CAN CREATE AMBIGUITY THAT WAS NOT THERE. "Nuevo sol" -> "sol" left
# Peru's option set as ['sol', 'solidus', ...]: two near-identical strings, one
# right, which is precisely the guessing-game this pass exists to remove. The
# rename is still correct; the distractor has to move with it.
POST_RENAME_CONFLICT = {"wd:currency:Q419": ("solidus", "Guatemalan quetzal")}
RETENSE = {"wd:currency:Q844930", "wd:currency:Q221457", "wd:currency:Q133132",
           "wd:currency:Q207991", "wd:currency:Q842931", "wd:currency:Q2334526",
           "wd:currency:Q8733"}


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    present = {q[0] for q in qs}
    missing = [i for i in list(CULL) + list(RENAME) + list(RETENSE) if i not in present]
    if missing:
        print(f"WARNING: target ids absent: {missing}")

    keep, culled, renamed, retensed, swapped = [], [], [], [], []
    for q in qs:
        qid = q[0]
        if qid in CULL:
            culled.append((qid, q[1], q[2][q[3]]))
            continue

        if qid in RENAME:
            old, new = RENAME[qid]
            if old in q[2]:
                q[2][q[2].index(old)] = new
                if q[6]:
                    q[6] = q[6].replace(f"→ {old}.", f"→ {new}.", 1)
                    q[6] = re.sub(rf"\b{re.escape(old)}\b", new, q[6])
                renamed.append((qid, old, new))

        if qid in POST_RENAME_CONFLICT:
            old, new = POST_RENAME_CONFLICT[qid]
            if old in q[2] and new not in q[2]:
                q[2][q[2].index(old)] = new
                swapped.append((qid, "post-rename lookalike", new))

        if BANNED_OPTION in q[2]:
            i = q[2].index(BANNED_OPTION)
            repl = next(c for c in SWAP_POOL if c not in q[2])
            q[2][i] = repl
            swapped.append((qid, q[1][:44], repl))

        if qid in RETENSE:
            new = re.sub(r"^What currency is used in ", "What currency was used in ", q[1])
            if new != q[1]:
                q[1] = new
                if q[6]:
                    q[6] = re.sub(r"^(.*?) is the official currency",
                                  r"\1 was the official currency", q[6])
                retensed.append((qid, new))
        keep.append(q)

    for name, rows in (("CULLED", culled), ("RENAMED", renamed),
                       ("DISTRACTOR SWAPPED", swapped), ("TENSE-FLIPPED", retensed)):
        print(f"\n{name}: {len(rows)}")
        for r in rows:
            print(f"    {r}")

    if not (culled or renamed or retensed or swapped):
        print("\nnothing to do")
        return
    doc["questions"] = keep
    tomb = doc.setdefault("tombstones", {}).setdefault("corpus", {})
    for qid, _, _ in culled:
        tomb[qid] = CULL[qid]
    doc["count"] = len(keep)
    doc["version"] = md5(json.dumps(
        keep, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} -> {len(keep)}   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
