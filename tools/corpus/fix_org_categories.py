#!/usr/bin/env python3
"""Refile companies, brands and clubs that landed in a person-shaped category.

Found while fixing the Closest Call inception verb: picking the verb by category
turned "In what year was Netflix founded?" into "Netflix formed", because Netflix
is filed under `music`. Manchester United is too. Checking the whole corpus
against the one-line description each subject carries turns up 43 organizations
in the wrong place — Toyota, Peugeot, Renault, Ryanair and Citroen under
`history`; Gatorade under `science`; Mercedes-Benz and Celtic F.C. under `music`.

Why it matters beyond tidiness: the category is what the player PICKS. A History
round that asks about Peugeot is the same "unintended question" complaint as
Create returning John Denver for Denver, and Business is the thinnest category in
the corpus (2,777 rows), so the rows are missing from exactly the place someone
would look for them.

Scope is deliberately narrow. This does NOT re-derive the categorizer in
`recategorize_and_clean.py` — that one reads a PERSON's occupation and is right
about people. It only moves subjects whose description names an organization
outright, and only when they are not currently in `business`/`sports`.

Dual-role PEOPLE are left alone on purpose. "American vocalist and actress" is
defensible under either music or screen, and 4.1% of subjects look
"miscategorized" by a naive description check almost entirely because of them —
reshuffling those would be churn, not a fix.

    python3 tools/corpus/fix_org_categories.py [--apply] [--check]

Then run tools/corpus/resync_corpus.sh to push it to every platform and
re-verify the Daily golden.
"""
import argparse
import collections
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from quality_gate import readable_description, copula_type                      # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORPUS = ROOT / "assets" / "corpus.json"

# Type nouns that name an organization rather than describe a person.
#
# `bank` is deliberately absent: it matched "City in the West Bank" and
# "President of the European Central Bank", making a Palestinian city and a
# central banker's job read as companies. Word-bounded matching does not save you
# from a word that is genuinely part of another name — the same trap as matching
# "Denver" inside "John Denver".
ORG = re.compile(
    r'\b(company|corporation|multinational|conglomerate|retailer|airline|'
    r'automaker|automotive brand|car brand|carmaker|manufacturer|streaming service|'
    r'brand of|e-commerce|software company|technology company|brewery|'
    r'supermarket|holding company|professional services network|'
    r'football club|soccer club|sports club|basketball team|baseball team)\b', re.I)

# If the description describes a PERSON, any organization word in it belongs to
# their employer, not to them: "English business magnate", "President of ...".
PERSON = re.compile(
    r'\b(singer|actor|actress|musician|footballer|magnate|oligarch|businessman|'
    r'businesswoman|entrepreneur|president of|writer|author|player|executive|'
    # "Easy Company soldier and jurist" is a man, and Easy Company is an infantry
    # unit — the only "company" in the corpus that fields a rifle.
    r'soldier|jurist|officer|general)\b', re.I)

# Phrases where an organization word is doing a different job entirely: a
# municipal corporation is a town council, and a vocal group is a band.
NOT_ORG = re.compile(r'\b(municipal corporation|vocal group|musical group|'
                     r'company rule|theatre company|dance company|opera company)\b', re.I)

CLUB = re.compile(r'\b(football club|soccer club|sports club|basketball team|baseball team)\b', re.I)

# Everything below exists because the description field does not always describe
# its subject — for a lot of rows it names the maker instead:
#
#   Mikoyan-Gurevich MiG-21  ->  "Russian Aircraft Corporation MiG"
#   Portal (video game)      ->  "Valve Corporation"
#   Mickey Mouse Clubhouse   ->  "The Walt Disney Company"
#   Victoria, British Columbia -> "Hudson's Bay Company"
#
# Matching an organization word anywhere in the string files a fighter jet, a
# video game, a cartoon and a city as businesses. Two guards fix it.

# 1. A description that is ENTIRELY a proper name is naming some other
#    organization, not describing this subject. A real description carries
#    lowercase type words: "American video streaming service", "French car brand".
def _is_proper_name(desc):
    words = [w for w in re.findall(r"[A-Za-z'&-]+", desc) if len(w) > 1]
    if len(words) < 2:
        return False
    return all(w[0].isupper() or w.lower() in {"the", "of", "and"} for w in words)


# 2. The organization word has to be the description's HEAD noun, not a
#    modifier buried inside it. Cut at the first preposition or comma and look at
#    what the phrase is actually about: "Easy Company soldier and jurist" is a
#    soldier, "Uprising against British Company rule" is an uprising, and
#    "Municipal corporation and tehsil in Uttarakhand" is a tehsil.
_HEAD_STOP = re.compile(r'\b(in|of|from|for|owned|based|located|against|by)\b|[,(]', re.I)
_HEAD_NOUN = re.compile(
    r'\b(company|corporation|conglomerate|retailer|airline|automaker|manufacturer|'
    r'service|brand|brewery|supermarket|network|chain|club|team|foundry|marketplace|'
    r'bookmaker|multinational)\b', re.I)


def _head_is_org(desc):
    head = _HEAD_STOP.split(desc, 1)[0]
    return bool(_HEAD_NOUN.search(head))


def descriptions(rows):
    """subject -> its one-line description, from the "Title: description" explanation.

    Rows whose explanation is a relation ("Netflix -> Tix") or a bare year carry
    no type information and are skipped.
    """
    out = {}
    for q in rows:
        # Same guard the gate uses: the description slot is only trustworthy as a
        # TYPE when the explanation really has the "Subject: description" shape
        # AND the description is a noun phrase. Reading prose refiled the Battle
        # of Plassey as BUSINESS, because its lead mentions the East India
        # Company. A repair that miscategorises is worse than one that abstains.
        d = readable_description(q[6] or "", q[7])
        if d == "PERSON-BY-DATES":
            d = None
        # A Wikidata one-liner if there is one; otherwise the predicate of a
        # sentence that is genuinely ABOUT this subject.
        d = d or copula_type(q[6] or "", q[7])
        if d and len(d) > 12:
            out.setdefault(q[7], d)
    return out


def misfiled(rows):
    """subject -> (description, current category, category it should have)."""
    desc = descriptions(rows)
    assigned = {}
    for q in rows:
        if q[7] in desc:
            assigned.setdefault(q[7], q[4])
    out = {}
    for subject, d in desc.items():
        if subject not in assigned or not ORG.search(d) or PERSON.search(d):
            continue
        if NOT_ORG.search(d) or _is_proper_name(d) or not _head_is_org(d):
            continue
        want = "sports" if CLUB.search(d) else "business"
        if assigned[subject] != want:
            out[subject] = (d, assigned[subject], want)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the corpus")
    ap.add_argument("--check", action="store_true", help="exit non-zero if any remain")
    args = ap.parse_args()

    data = json.load(open(CORPUS))
    rows = data["questions"]
    bad = misfiled(rows)
    affected = [q for q in rows if q[7] in bad]

    print(f"{len(bad)} misfiled organizations across {len(affected)} rows")
    moves = collections.Counter((v[1], v[2]) for v in bad.values())
    for (got, want), n in moves.most_common():
        print(f"   {n:>3} subjects  {got:10} -> {want}")
    for subject, (d, got, want) in sorted(bad.items())[:12]:
        print(f"      {subject:26} [{got:9} -> {want:8}] {d[:52]}")

    if args.check:
        return 1 if bad else 0
    if not args.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0

    for q in rows:
        if q[7] in bad:
            q[4] = bad[q[7]][2]
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CORPUS.write_text(f'{{"version":"{data["version"]}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CORPUS} — now run tools/corpus/resync_corpus.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
