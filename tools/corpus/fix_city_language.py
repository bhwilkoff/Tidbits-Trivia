#!/usr/bin/env python3
"""Drop "official language of <city>" questions whose answer is just the country's.

"Which of these is an official language of Thessaloniki?" answers Greek. The
subject's own description reads "Second-largest city in Greece" — the city name
tells you the country and the country tells you the language. Same for Ljubljana
(Slovene), Canberra (English), Bristol (English). 187 questions in the corpus ask
a country-level fact of a city.

They are NOT all bad, which is why this does not drop the lot. A city whose
official language differs from its country's is exactly the interesting case —
Barcelona, Brussels, Bolzano. So a row is dropped only when the city's answer is
also an official language of the country the description names; anything that
differs is left alone, because that one is a real question.

    python3 tools/corpus/fix_city_language.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import hashlib
import collections
import json
import pathlib
import re
import sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

STEM = "official language of"

# Rows the differs-from-its-country test clears only because the corpus records
# an INCOMPLETE language list for the country. Auckland answers English, and the
# corpus knows New Zealand only through Maori. Judged by reading, not inferred.
JUDGED_GIVEAWAY = {"rel:P37:Q37100"}
# A city or sub-national unit, and NOT a sovereign state in its own right.
CITY = re.compile(r"\b(city|town|village|county|municipality|district|borough|"
                  r"commune|prefecture|parish|neighborhood)\b", re.I)
SOVEREIGN = re.compile(r"\b(country|sovereign|kingdom|republic|empire|nation|"
                       r"caliphate|sultanate|duchy)\b", re.I)
# "Second-largest city in Greece." / "Capital city of Australia."
IN_COUNTRY = re.compile(r"\b(?:in|of)\s+([A-Z][\w'’-]*(?:\s+[A-Z][\w'’-]*){0,3})\s*[.,]?\s*$")


def first_sentence(expl):
    if ":" not in expl or "→" in expl:
        return ""
    d = expl.split(":", 1)[1].strip()
    return re.split(r"(?<=[.!?])\s", d, maxsplit=1)[0].strip()


def _stem(s):
    # Four, not five: "Norwegian"/"Norway" agree on four characters and
    # diverge on the fifth, and Bergen -> Norwegian is plainly inferable.
    return re.sub(r"[^a-z]", "", (s or "").lower())[:4]


def _same_language(answer, country, nationals):
    """Is the city's answer just the country's language under another name?

    A first pass compared the strings and "kept" Canberra -> English against
    Australia -> "Australian English", Beijing -> Chinese against "Standard
    Chinese", Limassol -> Greek against "Modern Greek". Those are one language
    named twice, and the question is still answerable from the city's name. So
    containment counts as the same, and so does sharing a stem with the COUNTRY
    (Bergen -> Norwegian, in Norway). Only a genuine difference survives —
    Dakar -> Wolof in French-speaking Senegal.
    """
    a = (answer or "").lower()
    for n in nationals:
        nl = n.lower()
        if a == nl or a in nl or nl in a:
            return True
    return _stem(answer) == _stem(country)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CORPUS.read_text())
    rows = data["questions"]

    desc = {}
    for q in rows:
        d = first_sentence(q[6] or "")
        if d and len(d) > 8 and not d[0].isdigit():
            desc.setdefault(q[7], d)

    # What the corpus itself says each COUNTRY's official languages are.
    country_langs = collections.defaultdict(set)
    for q in rows:
        if STEM in (q[1] or "") and q[2] and 0 <= q[3] < len(q[2]):
            subject_desc = desc.get(q[7], "")
            if not CITY.search(subject_desc):
                country_langs[q[7]].add(str(q[2][q[3]]))

    drop, kept = set(), []
    for q in rows:
        if STEM not in (q[1] or "") or not q[2] or not (0 <= q[3] < len(q[2])):
            continue
        d = desc.get(q[7], "")
        # The subject's own NAME settles it when the description does not. Once
        # descriptions became full prose, "Inca Empire" and "Federal Republic of
        # Central America" were read as cities because their leads mention the
        # cities they contained. Asking an empire its official language is a
        # perfectly good question; asking Auckland is not.
        if SOVEREIGN.search(q[7] or "") or not CITY.search(d) or SOVEREIGN.search(d):
            continue
        m = IN_COUNTRY.search(d.rstrip("."))
        country = m.group(1).strip() if m else None
        answer = str(q[2][q[3]])
        if q[0] in JUDGED_GIVEAWAY:
            drop.add(q[0])
        elif country and _same_language(answer, country, country_langs.get(country, set())):
            drop.add(q[0])
        elif country and country_langs.get(country):
            kept.append((q[1][:52], answer, country, sorted(country_langs[country])[:3]))
        else:
            drop.add(q[0])          # cannot show it differs, so it is a giveaway

    print(f"city official-language questions dropped: {len(drop)}")
    print(f"kept (the city genuinely differs from its country): {len(kept)}")
    for p, ans, ctry, cl in kept[:8]:
        print(f"   {p:54} -> {ans}  (in {ctry}, national: {cl})")
    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    out = [q for q in rows if q[0] not in drop]
    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{corpus_version(body)}","count":{len(out)},"questions":{body}}}')
    print(f"\n{len(rows)} -> {len(out)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
