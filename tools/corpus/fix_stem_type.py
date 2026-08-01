#!/usr/bin/env python3
"""Ask each subject a question its own kind of thing can answer.

`gen_facts.py` maps Wikidata's P17 ("country") to one stem, "In which country is
{k}?", and applies it to every subject that has the property. That reads fine for
a mountain and is nonsense for everything else:

    In which country is Russo-Ukrainian war?
    In which country is Normandy landings?
    In which country is Second Punic War?
    In which country is God Save the King?
    In which country is Germanwings Flight 9525?

The last one was the second question of the very first playtest of this session.
462 rows ask it of an event, an organization, a work or a person.

The stem now comes from the subject's own one-line description:

    event         In which country did the Normandy landings take place?
    organization  In which country is Nike, Inc. based?
    work/person   Which country is God Save the King from?
    place         unchanged

It also restores the article an event title drops ("the Normandy landings"),
which is why "In which country is White House?" read as broken even though the
country question is fair for a building.

    python3 tools/corpus/fix_stem_type.py [--apply]

Then run tools/corpus/resync_corpus.sh. `quality_gate.py` enforces the result as
STEM-TYPE so it cannot come back.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

# Subject kinds, from the corpus's own description line. Order matters: an
# "American rock band" is an organization before it is a work.
# An event only earns the "take place" stem when it happened in ONE identifiable
# country. A broad war did not: the Chaco War was Bolivia AND Paraguay, the
# Eastern Front spanned a dozen states, the Second Punic War ran across Spain,
# Italy and North Africa — and the corpus answers each with a single country. A
# question with two right answers marks a correct player wrong, so those rows are
# DROPPED rather than restemmed.
SPANNING = re.compile(r"\b(war\b|front\b|genocide|fitna|conflict|crusade|"
                      r"theatre|theater|campaign)\b", re.I)

# A recreational SPORT is not an event that happened somewhere. Airsoft's
# description is "shooting sport", which the event pattern happily matched:
# "In which country did the Airsoft take place?"
NOT_AN_EVENT = re.compile(r"\b(sport|game|hobby|pastime|activity|discipline)\b", re.I)

# "Which country" wants a country. A battle answered with "Western Roman Empire"
# or "Abbasid Caliphate" is asking about a state that no longer exists, which is
# a different question than the one the stem poses.
HISTORIC_STATE = re.compile(r"\b(empire|caliphate|khanate|sultanate|dynasty|"
                            r"soviet union|yugoslavia|czechoslovakia)\b", re.I)

KINDS = [
    # `flight` and `airsoft` are gone: they matched Flightradar24 (a website) and
    # Airsoft (a sport), producing "In which country did the Airsoft take place?".
    # Kept in step with quality_gate.NOT_A_PLACE — the two drifted once and the
    # gate caught a row the repair had skipped ("Civilian attack in Tokyo" was an
    # event to one and unknown to the other).
    ("event", r"\b(battle|siege|massacre|storming|liberation|invasion|landing|"
              r"uprising|revolution|coup|rebellion|shooting|bombing|earthquake|"
              r"eruption|hurricane|disaster|crash|attack|assassination|raid|"
              r"hijacking|riot|protest|election|treaty|"
              # A tournament happens somewhere, the same as a battle does.
              r"world cup|tournament|championship|olympics|games\b|regatta|"
              r"festival|summit|conference|expo)\b"),
    ("org",   r"\b(website|web service|online service|platform|app\b|"
              r"company|corporation|conglomerate|manufacturer|retailer|airline|brand|"
              r"club|team|university|bank|studio|publisher|broadcaster|agency|institute|"
              r"organisation|organization|party\b|band\b|label\b|airline)\b"),
    ("work",  r"\b(film|movie|song|album|single|novel|book|poem|series|sitcom|anime|"
              r"video game|manga|painting|opera|symphony|musical|anthem|sculpture|"
              # A machine is FROM a country, not IN one: "In which country is
              # Dassault Rafale?" of a fighter jet.
              r"aircraft|fighter|airliner|jet\b|helicopter|rocket|missile|tank\b|"
              r"car\b|automobile|locomotive|ship\b|submarine|spacecraft|satellite|"
              r"rifle|pistol|firearm|engine|processor|console)\b"),
    ("person", r"\b(born \d{4}|politician|footballer|actor|actress|singer|writer|player|"
               r"physicist|philosopher|emperor|monarch|composer|director|journalist)\b"),
]
KINDS = [(n, re.compile(p, re.I)) for n, p in KINDS]

STEMS = {
    "event": "In which country did {the}{k} take place?",
    "org":   "In which country is {k} based?",
    "work":  "Which country is {k} from?",
    "person": "Which country is {k} from?",
}
OLD = re.compile(r"^In which country is (.+)\?$")


def descriptions(rows):
    desc = {}
    for q in rows:
        e = q[6] or ""
        if ":" in e and "→" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            if d and not d[0].isdigit() and len(d) > 8:
                desc.setdefault(q[7], d)
    return desc


def kinds(desc):
    out = {}
    for name, d in desc.items():
        for n, rx in KINDS:
            if rx.search(d):
                out[name] = n
                break
    return out


def article(subject, kind):
    """Events read as "the Normandy landings"; the title drops the article."""
    if kind != "event":
        return ""
    if re.match(r"^(the|a|an)\b", subject, re.I):
        return ""
    return "the "


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]
    desc_of = descriptions(rows)
    kind_of = kinds(desc_of)

    changed = collections.Counter()
    examples = []
    drop = set()
    for q in rows:
        m = OLD.match(q[1] or "")
        if not m:
            continue
        subject = m.group(1)
        k = kind_of.get(q[7])
        d = desc_of.get(q[7], "")
        if SPANNING.search(d) and not re.search(r"\b(battle|siege|storming)\b", d, re.I):
            drop.add(q[0])
            continue
        if k == "event" and NOT_AN_EVENT.search(d):
            drop.add(q[0])
            continue
        if k == "event" and HISTORIC_STATE.search(str(q[2][q[3]]) if q[2] else ""):
            drop.add(q[0])
            continue
        if k not in STEMS:
            continue                      # a place, or a kind we cannot tell
        new = STEMS[k].format(k=subject, the=article(subject, k))
        if new != q[1]:
            if len(examples) < 8:
                examples.append((q[1], new))
            q[1] = new
            changed[k] += 1

    print(f"stems rewritten: {sum(changed.values())}  {dict(changed)}")
    print(f"to drop (event spans several countries): {len(drop)}")
    for before, after in examples:
        print(f"   {before}\n     -> {after}")
    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    kept = [q for q in rows if q[0] not in drop]
    body = json.dumps(kept, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(kept)},"questions":{body}}}')
    print(f"dropped {len(rows) - len(kept)} rows whose event spans more than one country")
    print(f"\nwrote {CORPUS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
