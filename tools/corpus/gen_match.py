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
            by_cat[cat][val].append((rank, key))
        # The cap is per (relation, CATEGORY). Sharing one budget across
        # categories let whichever sorted first consume the whole 60 and starved
        # the rest — screen fell to 27 rounds that way.
        for cat, byval in sorted(by_cat.items()):
            made = 0
            for bucket in byval.values():
                bucket.sort()
            values = sorted(byval, key=lambda v: byval[v][0])
            while made < PER_RELATION:
                live = [v for v in values if byval[v]]
                if len(live) < 4:
                    break
                grp = [(byval[v].pop(0)[1], v) for v in live[:4]]
                keys = [k for k, _ in grp]
                vals = [v for _, v in grp]
                expl = " · ".join(f"{k} → {v}" for k, v in grp)
                out.append([
                    f"match:{prefix.strip(':').split(':')[-1]}:{cat}:{made}:{keys[0]}",
                    prompt, keys, vals, cat, expl, "", "",
                ])
                made += 1

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
