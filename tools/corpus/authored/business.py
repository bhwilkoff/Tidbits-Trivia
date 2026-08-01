#!/usr/bin/env python3
"""Authored Business rounds for the three shapes no relation in the corpus can build.

`gen_business_shapes.py` closed Picture ID, Which First? and In Order for
Business by deriving them from Commons images and founding years. Match Up, Odd
One Out and Name as Many cannot be derived: Match Up needs a 1:1 relation the
corpus does not carry for companies (it has capital / currency / element-symbol /
author / composer / director), Odd One Out needs a grouping, and Name as Many
needs a curated list. So they are written by hand, here, as a committed source —
never edited directly into a generated artifact, which is how 22 Match-Up rounds
were lost once already (tools/corpus/authored/README.md).

Facts are the kind a general player can reason about — a founder, a headquarters
country, what a company actually sells — not trivia about revenue rankings that
change yearly and date the corpus.

    python3 tools/corpus/authored/business.py [--apply]
"""
import argparse
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
MIRRORS = ("assets", "TidbitsTrivia/Resources", "android/app/src/main/assets")
W = "https://en.wikipedia.org/wiki/"


def rid(prefix, *parts):
    return f"{prefix}:{hashlib.sha1('|'.join(parts).encode()).hexdigest()[:14]}"


# --- Match Up: 4 pairs each, no pair readable off the other side. -------------
MATCH = [
    ("Match each company to its founder.",
     [("Amazon", "Jeff Bezos"), ("Tesla Motors", "Martin Eberhard"),
      ("Alibaba Group", "Jack Ma"), ("Virgin Group", "Richard Branson")]),
    ("Match each company to its founder.",
     # No "Ford Motor Company -> Henry Ford": the answer is inside the question,
     # which is the same read-off-the-page giveaway the Match Up content pass
     # stripped out of 36 generated pairs.
     [("Standard Oil", "John D. Rockefeller"), ("Patagonia", "Yvon Chouinard"),
      ("Walmart", "Sam Walton"), ("IKEA", "Ingvar Kamprad")]),
    ("Match each company to the country it was founded in.",
     [("Nokia", "Finland"), ("Samsung", "South Korea"),
      ("Nestlé", "Switzerland"), ("Unilever", "Netherlands")]),
    ("Match each company to the country it was founded in.",
     [("Ryanair", "Ireland"), ("Aldi", "Germany"),
      ("Zara", "Spain"), ("Ferrari", "Italy")]),
    ("Match each brand to what it makes.",
     [("Rolex", "watches"), ("Michelin", "tyres"),
      ("Kodak", "photographic film"), ("Wedgwood", "pottery")]),
    ("Match each company to the industry it works in.",
     [("Maersk", "container shipping"), ("Schlumberger", "oilfield services"),
      ("Bloomberg", "financial data"), ("Deere & Company", "farm machinery")]),
    ("Match each airline to its home country.",
     [("Qantas", "Australia"), ("Cathay Pacific", "Hong Kong"),
      ("Lufthansa", "Germany"), ("Aeroflot", "Russia")]),
    ("Match each company to the product it became known for.",
     [("Gillette", "safety razors"), ("Dyson", "vacuum cleaners"),
      ("Lego", "plastic bricks"), ("Bic", "ballpoint pens")]),
]

# --- Odd One Out: three of a kind and an outsider, with the reason. -----------
ODD = [
    # The outsider is deliberately rotated through all four positions. Written
    # with it last every time, which is exactly the answer-position tell the play
    # audit flags (rule R8) — a player who notices scores without knowing anything.
    (["Volvo", "Volkswagen", "BMW", "Audi"], 0,
     "Volvo is Swedish — the other three are German carmakers."),
    (["Visa", "Pfizer", "Mastercard", "American Express"], 1,
     "Pfizer makes medicines — the other three are payment networks."),
    (["Nestlé", "Novartis", "Danone", "Roche"], 2,
     "Danone is French — the other three are Swiss companies."),
    (["Boeing", "Airbus", "Embraer", "Maersk"], 3,
     "Maersk is a shipping line — the other three build aircraft."),
    (["Ikea", "Zara", "H&M", "Uniqlo"], 0,
     "IKEA sells furniture — the other three are clothing retailers."),
    (["Shell", "Siemens", "BP", "TotalEnergies"], 1,
     "Siemens is an industrial and technology group — the other three are oil majors."),
    (["Toyota", "Honda", "Hyundai", "Nissan"], 2,
     "Hyundai is South Korean — the other three are Japanese carmakers."),
    (["Goldman Sachs", "Morgan Stanley", "JPMorgan Chase", "Unilever"], 3,
     "Unilever makes consumer goods — the other three are banks."),
    (["Kellogg's", "Coca-Cola", "PepsiCo", "Dr Pepper"], 0,
     "Kellogg's is a cereal maker — the other three are soft-drink companies."),
    (["Apple", "Nintendo", "Microsoft", "Alphabet"], 1,
     "Nintendo is Japanese — the other three are American technology giants."),
]

# --- Name as Many: each group is [canonical, alias...]. -----------------------
ENUM = [
    ("Name as many car brands owned by the Volkswagen Group as you can",
     [["Volkswagen", "VW"], ["Audi"], ["Porsche"], ["Skoda", "Škoda"],
      ["SEAT", "Seat"], ["Lamborghini"], ["Bentley"], ["Ducati"]]),
    ("Name as many of the five tech giants in the acronym FAANG as you can",
     [["Facebook", "Meta", "Meta Platforms"], ["Amazon"], ["Apple"],
      ["Netflix"], ["Google", "Alphabet"]]),
    # Tesla is deliberately absent: it was founded by Martin Eberhard and Marc
    # Tarpenning, which is what the Match Up round above says. Contradicting
    # itself across two modes is worse than a shorter list.
    ("Name as many companies founded by Elon Musk as you can",
     [["SpaceX", "Space X"], ["Neuralink"], ["The Boring Company", "Boring Company"],
      ["Zip2"], ["X.com"], ["xAI"]]),
    ("Name as many of the world's largest package delivery companies as you can",
     [["UPS", "United Parcel Service"], ["FedEx", "Federal Express"],
      ["DHL"], ["USPS", "United States Postal Service"], ["Royal Mail"]]),
]


def build():
    match_rows, odd_rows, enum_rows = [], [], []
    for prompt, pairs in MATCH:
        keys = [k for k, _ in pairs]
        vals = [v for _, v in pairs]
        match_rows.append([
            rid("match:business", prompt, keys[0]), prompt, keys, vals, "business",
            " · ".join(f"{k} → {v}" for k, v in pairs), "", "",
        ])
    for opts, correct, why in ODD:
        odd_rows.append([
            rid("odd:business", opts[0], opts[correct]),
            "Which of these is the odd one out?", opts, correct, "business", 3,
            why, opts[correct], W + opts[correct].replace(" ", "_"),
        ])
    for prompt, groups in ENUM:
        enum_rows.append([rid("enum:business", prompt), prompt, groups, "business", 60, ""])
    return {"match.json": match_rows, "oddoneout.json": odd_rows,
            "enumerate.json": enum_rows}


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
        print(f"{rel:18} {len(rows)} authored business rounds")
    if not args.apply:
        print("\n(dry run — pass --apply to append)")
        return
    print()
    for rel, rows in built.items():
        added, total = append(rel, rows)
        print(f"{rel:18} appended {added}, now {total} rows")


if __name__ == "__main__":
    main()
