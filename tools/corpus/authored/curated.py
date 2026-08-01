#!/usr/bin/env python3
"""The last content the corpus cannot derive: Business Name It, and Name as Many
for the four categories whose sets the corpus does not enumerate.

Everything else this session was fixed by deriving from the 128,638-row corpus —
Odd One Out went 238 -> 930 rows and Match Up 340 -> 1,145 that way. These two
resist it for real reasons:

  * **Name It** needs a clue that identifies exactly ONE answer. Generating from
    the corpus's one-line descriptions produced "American multinational
    technology company — name it." three times over for three different answers,
    and "United States — name it." seven times, because those rows hold a
    relation answer in the explanation field. A free-text question with more
    than one right answer marks correct players wrong, so the clue has to be
    written.
  * **Name as Many** needs a COMPLETE, well-defined set. The corpus enumerates a
    creator's body of work (that is where the 139 derived puzzles come from) and
    a continent's countries. It does not enumerate "the Grand Slam tournaments"
    or "the noble gases" — sets with a definite membership that simply is not in
    the data.

APPENDS by id; existing rows are untouched and re-runs add nothing.

    python3 tools/corpus/authored/curated.py [--apply]
"""
import argparse
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
MIRRORS = ("assets", "TidbitsTrivia/Resources", "android/app/src/main/assets")
W = "https://en.wikipedia.org/wiki/"


def rid(prefix, s):
    return f"{prefix}:{hashlib.sha1(s.encode()).hexdigest()[:14]}"


# --- Name It (Business): each clue must fit ONE company and no other. ---------
# Row shape: [id, prompt, answer, accepted(list), category, explanation, title, url]
TYPEANSWER = [
    ("Founded in a Seattle garage in 1994 selling books by mail, it now runs the "
     "world's largest cloud-computing business. Name it.",
     "Amazon", ["Amazon", "Amazon.com", "Amazon Inc"]),
    ("Two Stanford PhD students built its search engine in 1998; the parent company "
     "renamed itself Alphabet in 2015. Name the search company.",
     "Google", ["Google", "Google Inc", "Google LLC"]),
    ("A Swedish teenager founded it in 1943 selling pens and wallets by mail order; "
     "it is now the world's biggest furniture retailer. Name it.",
     "IKEA", ["IKEA", "Ikea"]),
    ("It began in 1971 as a single Seattle store selling beans, not drinks, and took "
     "its name from a character in Moby-Dick. Name it.",
     "Starbucks", ["Starbucks", "Starbucks Coffee"]),
    ("Founded in 1837 by a candle maker and a soap maker who had married sisters, it "
     "owns Tide, Pampers and Gillette. Name it.",
     "Procter & Gamble", ["Procter & Gamble", "Procter and Gamble", "P&G", "PG"]),
    ("A Japanese loom manufacturer spun off an automobile division in 1937; it became "
     "the world's largest carmaker. Name it.",
     "Toyota", ["Toyota", "Toyota Motor", "Toyota Motor Corporation"]),
    ("Its founder sold vacuum cleaners door to door before launching a DVD-by-mail "
     "service in 1997 that later killed Blockbuster. Name it.",
     "Netflix", ["Netflix"]),
    ("A Dutch company founded in 1891 making light bulbs, it later invented the "
     "compact cassette and co-invented the CD. Name it.",
     "Philips", ["Philips", "Koninklijke Philips"]),
    ("Founded in 1976 and named after a fruit, its first product was a circuit board "
     "sold without a case, keyboard or screen. Name it.",
     "Apple", ["Apple", "Apple Inc", "Apple Computer"]),
    ("A Korean trading company started in 1938 exporting dried fish and noodles; it is "
     "now the world's largest maker of memory chips. Name it.",
     "Samsung", ["Samsung", "Samsung Electronics"]),
    ("Its name is a portmanteau of the founder's surname and 'electronics'; it built "
     "the PlayStation and the Walkman. Name it.",
     "Sony", ["Sony", "Sony Corporation"]),
    ("Founded in 1903 in Milwaukee, it is the only major American motorcycle maker to "
     "survive the Great Depression. Name it.",
     "Harley-Davidson", ["Harley-Davidson", "Harley Davidson", "Harley"]),
    ("A Finnish paper mill founded in 1865 that became, for a decade, the world's "
     "biggest seller of mobile phones. Name it.",
     "Nokia", ["Nokia"]),
    ("This Italian carmaker's badge carries a prancing horse, given to its founder "
     "by the mother of a World War I flying ace. Name it.",
     "Ferrari", ["Ferrari"]),
]

# --- Name as Many: the four categories the corpus does not enumerate. ---------
ENUM = [
    ("history", "Name as many of the original Thirteen Colonies as you can",
     [["Delaware"], ["Pennsylvania"], ["New Jersey"], ["Georgia"], ["Connecticut"],
      ["Massachusetts"], ["Maryland"], ["South Carolina"], ["New Hampshire"],
      ["Virginia"], ["New York"], ["North Carolina"], ["Rhode Island"]]),
    ("history", "Name as many of the Allied 'Big Three' leaders of World War II as you can",
     [["Winston Churchill", "Churchill"], ["Franklin D. Roosevelt", "Roosevelt", "FDR"],
      ["Joseph Stalin", "Stalin"]]),
    ("history", "Name as many of the six wives of Henry VIII as you can",
     [["Catherine of Aragon"], ["Anne Boleyn"], ["Jane Seymour"],
      ["Anne of Cleves"], ["Catherine Howard"], ["Catherine Parr"]]),
    ("history", "Name as many of the Axis powers of World War II as you can",
     [["Germany"], ["Italy"], ["Japan"], ["Hungary"], ["Romania"], ["Bulgaria"]]),
    ("science", "Name as many of the noble gases as you can",
     [["Helium"], ["Neon"], ["Argon"], ["Krypton"], ["Xenon"], ["Radon"]]),
    ("science", "Name as many of the eight planets as you can",
     [["Mercury"], ["Venus"], ["Earth"], ["Mars"], ["Jupiter"], ["Saturn"],
      ["Uranus"], ["Neptune"]]),
    ("science", "Name as many of the four fundamental forces as you can",
     [["Gravity", "Gravitation"], ["Electromagnetism", "Electromagnetic force"],
      ["Strong nuclear force", "Strong force", "Strong interaction"],
      ["Weak nuclear force", "Weak force", "Weak interaction"]]),
    ("science", "Name as many of the states of matter as you can",
     [["Solid"], ["Liquid"], ["Gas"], ["Plasma"]]),
    ("sports", "Name as many of the tennis Grand Slam tournaments as you can",
     [["Australian Open"], ["French Open", "Roland Garros"], ["Wimbledon"],
      ["US Open", "United States Open"]]),
    ("sports", "Name as many sports in the modern pentathlon as you can",
     [["Fencing"], ["Swimming"], ["Equestrian", "Show jumping", "Riding"],
      ["Shooting"], ["Running", "Cross country"]]),
    ("sports", "Name as many of the four major North American pro sports leagues as you can",
     [["NFL", "National Football League"], ["NBA", "National Basketball Association"],
      ["MLB", "Major League Baseball"], ["NHL", "National Hockey League"]]),
    ("sports", "Name as many events in the decathlon as you can",
     [["100 metres", "100m"], ["Long jump"], ["Shot put"], ["High jump"],
      ["400 metres", "400m"], ["110 metres hurdles", "110m hurdles", "Hurdles"],
      ["Discus throw", "Discus"], ["Pole vault"], ["Javelin throw", "Javelin"],
      ["1500 metres", "1500m"]]),
    ("business", "Name as many airlines in the Star Alliance as you can",
     [["Lufthansa"], ["United Airlines", "United"], ["Air Canada"],
      ["Singapore Airlines"], ["Turkish Airlines"], ["ANA", "All Nippon Airways"],
      ["Swiss International Air Lines", "Swiss"]]),
    ("business", "Name as many brands owned by Unilever as you can",
     [["Dove"], ["Ben & Jerry's", "Ben and Jerrys"], ["Hellmann's", "Hellmanns"],
      ["Axe", "Lynx"], ["Magnum"], ["Vaseline"], ["Knorr"]]),
]


def build():
    ta = [[rid("type:business", p), p, ans, acc, "business", f"{ans}.", ans,
           W + ans.replace(" ", "_")] for p, ans, acc in TYPEANSWER]
    en = [[rid("enum:curated", p), p, groups, cat, 60, ""] for cat, p, groups in ENUM]
    return {"typeanswer.json": ta, "enumerate.json": en}


def append(rel, rows):
    base = json.load(open(ROOT / "assets" / rel))
    have = {r[0] for r in base["questions"]}
    added = [r for r in rows if r[0] not in have]
    all_rows = base["questions"] + added
    body = json.dumps(all_rows, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(all_rows)},"questions":{body}}}'
    for m in MIRRORS:
        p = ROOT / m / rel
        if p.exists():
            p.write_text(payload)
    return len(added), len(all_rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    built = build()
    for rel, rows in built.items():
        print(f"{rel:18} {len(rows)} curated rows")
    if not args.apply:
        print("\n(dry run — pass --apply to append)")
        return
    print()
    for rel, rows in built.items():
        added, total = append(rel, rows)
        print(f"{rel:18} appended {added}, now {total} rows")


if __name__ == "__main__":
    main()
