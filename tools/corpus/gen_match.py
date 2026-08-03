#!/usr/bin/env python3
"""Matching (Q5) — link each key to its value, from the corpus's 1:1 Wikidata
relations (capital / currency / element symbol / book author).

Groups four (key, value) pairs of the same relation into a matching question.
The client shows the keys in order and the values shuffled; the player links
each; scoring is the count of correct links. Keys are deduped and groups are
non-overlapping per relation.

Output: assets/match.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, keys(4), values(4 — parallel/correct), category,
            explanation, "", ""]

Usage: python3 gen_match.py
"""
import argparse, collections, hashlib, json, os, re, unicodedata
import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import genguard

# id-prefix -> (prompt, key-noun, value-noun). key = source title, value = answer.
# The key noun has to be true of every key the relation actually yields, not of
# the typical one. "Match each country to its capital" was asked with Idaho, West
# Virginia, Cornwall, Fuerteventura and the Mamluk Sultanate as keys; "Match each
# book to its author" was asked of LazyTown, Ozymandias and Hansel and Gretel;
# "Match each film to its director" of Glee and Final Fantasy VII. A prompt that
# misdescribes its own contents reads as a mistake even when the pairing is right.
# The one relation whose keys are NOT a single kind. Every other relation yields
# one type by construction (an element has a symbol, a work has an author), but
# "country of" applies to a football club, a battle, a manga and a statue alike,
# so the prompt shipped as "Match each of these to its country." and the rounds
# mixed types: 304 of 324 of them, including
#
#     Anne of Green Gables · Bauhaus · Naruto · Manneken Pis
#
# Grouping by Wikidata type instead makes the round coherent AND nameable, at the
# cost of the rounds whose type has fewer than four distinct countries.
TYPED_RELATION = "rel:P17:"

# Type labels that must not become a prompt.
#
# TAUTOLOGY: any label containing "country" gives "Match each historical country
# to its country."
#
# JARGON: Wikidata's ontology words are not English a player reads — "aspect of
# history", "occurrence", "human settlement", "first-level administrative
# division". They describe a database, not a thing.
#
# TONE: "Match each massacre to its country", "...each genocide...", "...each
# terrorist attack..." turn atrocities into a matching puzzle. The facts belong
# in the corpus and these questions are askable in prose; the MATCHING GRID is
# what makes them flippant, so the exclusion is about the shape, not the subject.
#
# A label naming a country ("municipality of Romania") also leaks the answer, and
# that is caught per-round below rather than by name.
BAD_TYPE_LABEL = (
    "country", "aspect of history", "occurrence", "human settlement",
    "first-level administrative division", "historical ethnic group",
    "type of sport", "rapid transit", "disputed territory",
    "genocide", "massacre", "mass murder", "terrorist attack",
)

RELATIONS = {
    "wd:capital:":    ("Match each place to its capital.", "place", "capital"),
    "wd:currency:":   ("Match each place to its currency.", "place", "currency"),
    "wd:elemSymbol:": ("Match each element to its symbol.", "element", "symbol"),
    "wd:author:":     ("Match each work to its author.", "work", "author"),
    "wd:composer:":   ("Match each work to its composer.", "work", "composer"),
    "wd:director:":   ("Match each title to its director.", "title", "director"),
    # Four relations the corpus already holds that this never touched. Without
    # them Match Up had 11 sports / 8 business / 13 history rows against a 6-pair
    # round, so a player's THIRD round in those categories ran 65% on-category.
    "rel:P17:":       ("Match each of these to its country.", "subject", "country"),
    "rel:P112:":      ("Match each organization to its founder.", "organization", "founder"),
    # NOT "song ... artist": Wikidata's `performer` covers an ACTOR playing a
    # role as well as a musician playing a track, so the round rendered as "Match
    # each song to the artist who performed it" over Rocket Raccoon, Scarecrow and
    # Shazam — characters and their voice actors. Found by reading the screen.
    "rel:P175:":      ("Match each role or song to its performer.", "work", "performer"),
    "rel:P170:":      ("Match each work to its creator.", "work", "creator"),
}
PER_RELATION = 60


# Values that are a CATEGORY of money rather than a named currency. In a 1:1
# matching grid the value has to identify one key: "gold", "coin", "cash" and
# "bimetallism" could each belong to several of the four places on screen, so the
# player cannot reason their way to a link even knowing the facts. Named
# historical currencies (ducat, thaler, peseta, drachma) are fine and stay.
GENERIC_VALUES = {
    "coin", "cash", "gold", "silver", "currency", "bimetallism", "shell money",
    "pearl", "cocoa bean", "tin ingot", "spade money", "ancient chinese coinage",
    "ancient drachma", "commodity money", "barter",
}

# Keys the corpus categorizer filed as `geography` that are not places at all.
# Roblox is in the currency relation because its row is categorized geography —
# the same misfiling that has Netflix and Manchester United under `music`. The
# real fix is the categorizer; until then a prompt that says "Match each place to
# its currency" must not be handed a game platform.
NON_PLACE_KEYS = {"Roblox"}


# Shared function words say nothing about a pair.
_STOPWORDS = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for",
              "de", "la", "le", "el", "s", "is", "was", "or"}


def _fold(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def name_overlap(key, val):
    """Can this pair be linked by reading alone, with no knowledge at all?

    Match-Up shows keys beside shuffled values, so a pair whose two sides share
    their words is solved by looking — "Singapore -> Singapore dollar",
    "Real Madrid -> Madrid", "The Autobiography of Malcolm X -> Malcolm X". An
    earlier pass declined to touch these on the grounds that a city-state's
    capital is a real fact, which is true of the FACT and not of the QUESTION:
    nothing here is being recalled.

    It also compounds, which is the part that makes it worth fixing rather than
    tolerating. Linking is 1:1 over four pairs, so a free pair does not cost one
    quarter of the round — it removes a value from every other pair's candidate
    set, and two free pairs leave a two-way choice.

    Partial overlaps that still need recall are deliberately NOT caught: Tunisia
    -> Tunis and El Salvador -> San Salvador share no whole word.
    """
    kw, vw = set(_fold(key).split()), set(_fold(val).split())
    if not kw or not vw:
        return False
    if kw.issubset(vw) or vw.issubset(kw):
        return True
    # Any shared SIGNIFICANT word gives the pair away, not just a whole-side
    # containment: "Trader Joe's -> Joe Coulombe" and "Manchester United ->
    # Manchester" were slipping through because neither side contains the other
    # and the stem rule below needs four characters ("joe" is three). Stopwords
    # are excluded or "Mausoleum of Qin Shi Huang -> People's Republic of China"
    # would be rejected for sharing the word "of".
    if (kw & vw) - _STOPWORDS:
        return True
    # Whole-word containment alone misses the adjectival form, which is just as
    # free to read off: "Russia -> Russian ruble", "India -> Indian rupee",
    # "Poland -> Polish zloty". A shared stem of four or more characters catches
    # those while leaving pairs that need recall — "China -> Chinese yuan" shares
    # no such stem, and neither does "Germany -> Deutsche Mark".
    for a in kw:
        for b in vw:
            if len(a) >= 4 and len(b) >= 4 and (a.startswith(b) or b.startswith(a)):
                return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--difficulty", default="../../assets/difficulty.json")
    ap.add_argument("--out", default="../../assets/match.json")
    genguard.add_args(ap)
    args = ap.parse_args()

    qs = json.load(open(args.corpus))["questions"]
    # Prominence, from the same pageview-derived overlay Ladder uses (1 = famous,
    # 5 = obscure). Pairs were previously taken in whatever order they appeared in
    # the corpus, which was survivable when the corpus was small and is not now
    # that it carries thousands of historical polities: a straight regeneration
    # produced rounds like "Hoysala Kingdom -> Halebidu · Sultanate of Hobyo ->
    # Hobyow". Nobody can play that, and a round nobody can play is worse than the
    # name-overlap giveaway this pass set out to remove. Famous subjects first.
    diff = json.load(open(args.difficulty))["difficulty"]

    out = []
    # country-of is the one relation whose keys are not one kind of thing, so it
    # is grouped by Wikidata TYPE and names that type in the prompt. See the note
    # on TYPED_RELATION below.
    p31_of, type_label = {}, {}
    _src = os.path.join(os.path.dirname(__file__), "corpus_source.sqlite")
    _lab = os.path.join(os.path.dirname(__file__), "p31_labels.json")
    if os.path.exists(_src) and os.path.exists(_lab):
        import sqlite3
        _db = sqlite3.connect("file:%s?mode=ro" % _src, uri=True)
        p31_of = {t: (v or "").split(",")[0]
                  for t, v in _db.execute("select title, p31 from subject")}
        _db.close()
        type_label = json.load(open(_lab))

    for prefix, (prompt, _kn, _vn) in RELATIONS.items():
        # Collect deduped (key, value, category) pairs for this relation.
        pairs, seen = [], set()
        for q in qs:
            if not q[0].startswith(prefix):
                continue
            key = q[7]                    # source title (country / element / book)
            val = q[2][q[3]]              # the answer (capital / symbol / author)
            if not key or not val or key in seen or key == val:
                continue
            if name_overlap(key, val):
                continue
            if val.strip().lower() in GENERIC_VALUES or key in NON_PLACE_KEYS:
                continue
            seen.add(key)
            # The overlay is keyed on the Wikipedia title (underscored), which is
            # what the source URL carries; fall back to "obscure" so an unranked
            # subject sorts last rather than first.
            title = q[8].split("/wiki/")[-1] if "/wiki/" in (q[8] or "") else ""
            # The row's OWN difficulty ranks everything (it was rebuilt to an exact
            # distribution over the whole corpus); the pageview overlay covers only
            # ~12k titles and breaks ties. Ranking by the overlay alone left every
            # element round made of moscovium, oganesson and tennessine, because no
            # element is in it and they all defaulted to "obscure".
            pairs.append((key, val, q[4], (q[5], diff.get(title, 5))))
        # Most recognizable first, so a round is playable. Stable within a rank,
        # so the output stays deterministic across runs.
        pairs.sort(key=lambda p: p[3])   # (row difficulty, pageview rank)
        # Rounds are built by round-robin over the VALUE buckets, within one
        # category, so the four values in a round are distinct by construction and
        # the round never mixes categories.
        #
        # This used to take four CONSECUTIVE pairs and discard the group whenever
        # two shared a value. That works for capital-of, where every country has
        # its own answer, and fails completely for country-of or creator-of, where
        # dozens of subjects legitimately share one — it threw away nearly every
        # candidate and the four relations above produced ZERO rounds.
        by_cat = collections.defaultdict(lambda: collections.defaultdict(list))
        for key, val, cat, rank in pairs:
            lane = cat
            if prefix == TYPED_RELATION:
                ty = p31_of.get(key)
                if not ty or ty not in type_label:
                    continue
                _lab = type_label[ty].lower()
                if any(b in _lab for b in BAD_TYPE_LABEL):
                    continue
                lane = (cat, ty)
            by_cat[lane][val].append((rank, key))
        # The cap is per (relation, CATEGORY). Sharing one budget across
        # categories let whichever sorted first consume the whole 60 and starved
        # the rest — screen fell to 27 rounds that way.
        # The cap stays per (relation, CATEGORY) even when a relation is split
        # into type lanes, so grouping by type changes what a round CONTAINS
        # without changing how many of them each category gets. Budgeting per lane
        # instead took geography from 270 rounds to 430, purely because city, big
        # city, island, region and river are all geography.
        # The cap is per (relation, CATEGORY) even when a relation is split into
        # type lanes: grouping by type changes what a round CONTAINS, not how many
        # each category gets. Budgeting per LANE took geography from 270 rounds to
        # 430 purely because city, big city, island, region and river are all
        # geography; dividing the budget evenly instead capped every lane at two
        # and cut country-of from 324 rounds to 102. Round-robin across the lanes
        # spends the category's whole budget without letting the alphabetically
        # first type eat it.
        lanes = sorted(by_cat.items(), key=lambda kv: str(kv[0]))
        for cat in sorted({(l[0] if isinstance(l, tuple) else l) for l, _ in lanes}):
            mine = [(l, bv) for l, bv in lanes
                    if (l[0] if isinstance(l, tuple) else l) == cat]
            for _, byval in mine:
                for bucket in byval.values():
                    bucket.sort()
            order = {id(bv): sorted(bv, key=lambda v: bv[v][0]) for _, bv in mine}
            made, live_lanes = 0, list(mine)
            while made < PER_RELATION and live_lanes:
                progressed = False
                for lane, byval in list(live_lanes):
                    if made >= PER_RELATION:
                        break
                    values = order[id(byval)]
                    live = [v for v in values if byval[v]]
                    if len(live) < 4:
                        live_lanes.remove((lane, byval))
                        continue
                    grp = [(byval[v].pop(0)[1], v) for v in live[:4]]
                    keys = [k for k, _ in grp]
                    vals = [v for _, v in grp]
                    # "Match each municipality of Romania to its country" hands
                    # the answer to any round that includes Romania.
                    if isinstance(lane, tuple) and any(
                            v.lower() in type_label[lane[1]].lower() for v in vals):
                        continue
                    expl = " \u00b7 ".join(f"{k} \u2192 {v}" for k, v in grp)
                    rel = prefix.strip(":").split(":")[-1]
                    if isinstance(lane, tuple):
                        # "Match each football club to its country." A round of four
                        # football clubs can say so; a round of a manga, a statue, an
                        # art school and a novel could only say "these".
                        round_prompt = "Match each %s to its country." % type_label[lane[1]]
                        rid = f"match:{rel}:{lane[1]}:{cat}:{made}:{keys[0]}"
                    else:
                        round_prompt = prompt
                        rid = f"match:{rel}:{cat}:{made}:{keys[0]}"
                    out.append([rid, round_prompt, keys, vals, cat, expl, "", ""])
                    made += 1
                    progressed = True
                if not progressed:
                    break

    # Hand-authored rounds the Wikidata relations cannot produce — "Match each NBA
    # legend to the team he is most associated with", "Match each famous battle to
    # the war it was part of". These are the ONLY sports and history coverage this
    # mode has, and until now they lived nowhere but the generated artifact: the
    # first regeneration silently deleted all 22 of them, taking matching x sports
    # from 11 rounds to 0. They are a committed input now, so regenerating is safe.
    authored_path = os.path.join(os.path.dirname(__file__), "authored", "match.json")
    if os.path.exists(authored_path):
        authored = json.load(open(authored_path))["questions"]
        have = {q[0] for q in out}
        out += [r for r in authored if r[0] not in have]
        print(f"merged {len(authored)} authored rounds")

    out = genguard.merge('match', out, args.out,

                         regenerate=args.regenerate, prune=args.prune)

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "match.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "match.json")
    # `--out /tmp/x.json` reads as "write somewhere harmless so I can look",
    # and it did not: these tracked copies were written regardless, so a safety
    # check that generated to a temp file silently replaced the iOS and Android
    # copies. Only the default --out touches the mirrors now.
    _mirrors = [res_copy, and_copy] if args.out == ap.get_default('out') else []
    for path in [args.out] + _mirrors:
        with open(path, "w") as f:
            f.write(payload)
    from collections import Counter
    print(f"wrote {len(out)} matching questions (version {version})")
    print("by relation:", dict(Counter(q[0].split(':')[1] for q in out)))
    for q in out[:4]:
        print("  ", q[1], "|", q[5])


if __name__ == "__main__":
    main()
