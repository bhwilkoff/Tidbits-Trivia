"""Countries listed with a currency they stopped using.

Found by READING all 258 "What currency is used in X?" answers rather than
diffing them against another corpus field. The cross-check I tried first --
compare each `rev:P38` row against the forward `wd:currency` row for the same
country -- reported 0 mismatches and was structurally incapable of finding
anything: BOTH rows are generated from the same Wikidata P38 claim, so when the
claim is stale both rows are stale and they agree with each other perfectly.
Argentina's forward row and reverse row both say "peso moneda nacional",
withdrawn in 1970. Two sources that share an upstream error are one source.

The real defects, all present tense about a currency that is gone:

  EUROZONE MEMBERS LISTED WITH THEIR PRE-EURO CURRENCY -- Germany answering
  "Deutsche Mark" is the kind of error a player notices immediately.
      Germany -> Deutsche Mark        Lithuania -> Lithuanian litas
      Slovakia -> Slovak koruna       Republic of Ireland -> Irish pound
      San Marino -> Sammarinese lira  Croatia -> Croatian dinar
  ARGENTINA -> peso moneda nacional (replaced 1970).

Repaired, not culled -- "What currency is used in Germany?" is a good question
with a wrong answer, and the fix is one string:

  * San Marino already had "euro" among its options, so only the index moves.
  * Germany, Lithuania, Slovakia, Ireland and Argentina had no correct option, so
    the WRONG ANSWER STRING is replaced in place and the index stays. Their other
    three distractors were checked by eye and none is confusable with the new
    answer (Belize dollar / Nicaraguan cordoba / Artsakh dram, and so on).
  * Croatia needed one more substitution: its distractors included "European
    Currency Unit", the euro's own predecessor, which is not a fair wrong answer
    once "euro" is the right one. That distractor becomes "Norwegian krone".

  * The three `rev:P38` rows ask the question from the currency's side ("Which
    country uses the Irish pound...?"), where the tense IS the fix and the answer
    was already right: "uses" -> "used" keeps all three.

THE EXPLANATION IS PART OF THE ROW. These carry a generated lead -- "Croatia ->
Croatian dinar." and "The peso moneda nacional is the official currency of
Argentina." -- which would have gone on contradicting the repaired answer on the
reveal screen. Each lead is rewritten with its row.
"""
import json
import re
from hashlib import md5
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

# id -> (wrong answer string, correct answer string)
REPOINT = {
    "wd:currency:Q183": ("Deutsche Mark", "euro"),
    "wd:currency:Q37": ("Lithuanian litas", "euro"),
    "wd:currency:Q214": ("Slovak koruna", "euro"),
    "wd:currency:Q27": ("Irish pound", "euro"),
    "wd:currency:Q238": ("Sammarinese lira", "euro"),
    "wd:currency:Q224": ("Croatian dinar", "euro"),
    "wd:currency:Q414": ("peso moneda nacional", "Argentine peso"),
}
# The euro's predecessor is not a fair distractor for a question whose answer is
# now the euro.
SWAP_DISTRACTOR = {"wd:currency:Q224": ("European Currency Unit", "Norwegian krone")}
# Reverse rows: the answer is right, the tense is not.
RETENSE = {"rev:P38:Q27", "rev:P38:Q214", "rev:P38:Q238", "rev:P38:Q414"}


def main():
    doc = json.loads(CORPUS.read_text())
    qs = doc["questions"]
    seen = {q[0] for q in qs}
    missing = [i for i in list(REPOINT) + list(RETENSE) if i not in seen]
    if missing:
        print(f"WARNING: target ids absent from the corpus: {missing}")

    changed = []
    for q in qs:
        qid = q[0]
        if qid in REPOINT:
            wrong, right = REPOINT[qid]
            if q[2][q[3]] != wrong:
                continue
            if right in q[2]:                       # already a valid option
                q[3] = q[2].index(right)
            else:
                q[2][q[3]] = right
            if qid in SWAP_DISTRACTOR:
                old, new = SWAP_DISTRACTOR[qid]
                if old in q[2]:
                    q[2][q[2].index(old)] = new
            if q[6]:
                q[6] = q[6].replace(f"→ {wrong}.", f"→ {right}.", 1)
                q[6] = re.sub(rf"^(.*?) is {re.escape(wrong)}\.", rf"\1 is {right}.", q[6])
            changed.append((qid, q[1], wrong, right))
        elif qid in RETENSE:
            new = re.sub(r"^Which country uses the ", "Which country used the ", q[1])
            if new != q[1]:
                q[1] = new
                if q[6]:
                    q[6] = re.sub(r"^The (.*?) is the official currency of",
                                  r"The \1 was the official currency of", q[6])
                changed.append((qid, q[1], "uses", "used"))

    print(f"changed: {len(changed)}")
    for qid, prompt, a, b in changed:
        print(f"    {qid:22} {prompt[:62]}\n    {'':22}   {a!r} -> {b!r}")
    if not changed:
        print("nothing to do")
        return

    doc["count"] = len(qs)
    doc["version"] = md5(json.dumps(
        qs, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()[:12]
    CORPUS.write_text(json.dumps(doc, ensure_ascii=False))
    print(f"\n{len(qs)} rows   version {doc['version']}  count {doc['count']}")


if __name__ == "__main__":
    main()
