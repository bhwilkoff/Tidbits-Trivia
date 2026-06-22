#!/usr/bin/env python3
"""Two corpus-quality fixes that need only the shipped corpus.json (no source DB):

1. RECATEGORIZE clearly-miscategorized PEOPLE. Each person's one-line description
   (e.g. "American football linebacker") implies a domain. We reassign the row's
   category ONLY when the description does not support the CURRENT category at all
   — i.e. a genuine error (a footballer filed under Film & TV), never an
   ambiguous multi-role case (a "singer and actress" already in Film & TV is left
   alone, since both domains are defensible).

2. STRIP option disambiguators. A distractor like "John Thomson (photographer)"
   shown beside bare names is a dead giveaway. We drop the trailing "(...)" from
   every option in a row — but only when that introduces no collision (so
   "Georgia (U.S. state)" vs "Georgia (country)" keeps its qualifier).

Writes corpus.json (web/Android) + corpus.sqlite (iOS). Rerun gen_*.py after so
every bundled set inherits the fixes. Dry-run by default; pass --apply to write.

Usage: python3 recategorize_and_clean.py [--apply]
"""
import argparse, hashlib, json, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_picture as gp  # subject_description() + _classify()

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CORPUS = os.path.join(ROOT, "assets", "corpus.json")

# Per-category domain detectors over a person's description. A category is
# "supported" if its pattern matches; priority order breaks ties when the
# current category is unsupported.
DOMAINS = [
    # "jockey" is guarded so "disc jockey" (a DJ) doesn't read as sport; "coach"
    # is omitted because "vocal coach"/"acting coach" aren't sports — a real
    # sports coach is caught by the sport name ("football coach" -> football).
    ("sports", re.compile(r'\b(football|basketball|baseball|soccer|hockey|tennis|golf|cricket|rugby|boxing|boxer|athlete|olympic|gymnast|sprinter|swimmer|cyclist|wrestler|footballer|quarterback|linebacker|cornerback|halfback|fullback|goalkeeper|midfielder|striker|batsman|bowler|pitcher|catcher|shortstop|(?<!disc )jockey|rower|fencer|weightlifter|hurdler|decathlete|figure skater|speed skater|snowboarder|surfer|racing driver|formula one|nascar|sportsman|sportswoman|referee|umpire)\b', re.I)),
    ("science", re.compile(r'\b(physicist|chemist|biologist|mathematician|astronomer|scientist|engineer|inventor|geologist|botanist|economist|psychologist|naturalist|physician|biochemist|virologist|geneticist|paleontologist|aerospace|zoologist|ecologist|neuroscientist|statistician)\b', re.I)),
    ("music", re.compile(r'\b(singer|musician|composer|rapper|guitarist|pianist|drummer|songwriter|conductor|violinist|cellist|trumpeter|saxophonist|opera singer|record producer|disc jockey|vocalist|\bDJ\b)\b', re.I)),
    ("screen", re.compile(r'\b(actor|actress|film director|filmmaker|screenwriter|film producer|television presenter|television host|talk show host|voice actor|comedian|television|sitcom|video game)\b', re.I)),
    ("arts", re.compile(r'\b(novelist|poet|playwright|author|writer|painter|sculptor|philosopher|essayist|cartoonist|illustrator|animator|architect|photographer|dramatist|art historian|fashion designer|journalist|theologian)\b', re.I)),
    ("history", re.compile(r'\b(king|queen|emperor|empress|president|politician|monarch|general|prime minister|statesman|pharaoh|dictator|senator|revolutionary|warlord|chieftain|admiral|marshal|nobleman|aristocrat|duke|duchess|sultan|caliph|tsar|chancellor|governor|viceroy|diplomat|activist)\b', re.I)),
]


def supported(desc):
    return [cat for cat, rx in DOMAINS if rx.search(desc)]


def strip_disamb(opt):
    return re.sub(r'\s*\([^)]*\)\s*$', '', opt).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    corpus = json.load(open(CORPUS))
    qs = corpus["questions"]

    recat = 0
    opt_cleaned = 0
    from collections import Counter
    trans = Counter()
    for q in qs:
        ans = q[2][q[3]]
        desc = gp.subject_description(ans, q[6] if len(q) > 6 else "")

        # 1. recategorize people whose current category is unsupported
        if desc and gp._classify(desc) == "person":
            sup = supported(desc)
            if sup and q[4] not in sup:
                new = sup[0]
                trans[(q[4], new)] += 1
                recat += 1
                if args.apply:
                    q[4] = new

        # 2. strip option disambiguators (collision-guarded, per row)
        opts = q[2]
        if any(re.search(r'\([^)]*\)\s*$', o) for o in opts):
            stripped = [strip_disamb(o) for o in opts]
            if len(set(stripped)) == len(opts) and all(stripped):
                opt_cleaned += 1
                if args.apply:
                    q[2] = stripped

    print(f"recategorized people : {recat}")
    for (a, b), n in trans.most_common(12):
        print(f"    {a:9} -> {b:9} : {n}")
    print(f"option rows cleaned  : {opt_cleaned}")

    if not args.apply:
        print("\n(dry run — pass --apply to write corpus.json + sqlite, then rerun gen_*.py)")
        return

    body = json.dumps(qs, ensure_ascii=False, separators=(",", ":"))
    ver = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{ver}","count":{len(qs)},"questions":{body}}}'
    for p in (CORPUS, os.path.join(ROOT, "android/app/src/main/assets/corpus.json")):
        open(p, "w").write(payload)
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "sources"))
    import build_corpus
    build_corpus.write_sqlite(qs, build_corpus.IOS_SQLITE)
    print(f"\nwrote corpus.json (web/Android) + corpus.sqlite (iOS), version {ver}")
    print("now rerun gen_*.py so every bundled set inherits the fixes")


if __name__ == "__main__":
    main()
