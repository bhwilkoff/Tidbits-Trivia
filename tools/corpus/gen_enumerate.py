#!/usr/bin/env python3
"""Enumeration / list mode (Q8) — "name as many X in 60s".

Each puzzle is a prompt + a set of accepted-answer GROUPS; the player types
answers against a live timer and each unique correct answer fills one slot of a
grid. A group is [canonical, alias1, alias2, ...] — input is matched (case /
punctuation / diacritic / "the"-insensitive, mirroring the type-answer
normalizer) against ANY string in an unfilled group, which then fills.

Two sources:
  1. Corpus continent->countries (the same wd:continent data Odd-One-Out uses),
     enriched with E1 "also known as" aliases (United States -> US / USA / ...).
  2. A few canonical, well-bounded hardcoded sets (planets, elements, oceans,
     Great Lakes, continents) — high recall value, alias-friendly.

Output: assets/enumerate.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, groups, category, seconds, source_url]
  groups = [[canonical, alias, ...], ...]

Usage: python3 gen_enumerate.py
"""
import hashlib, json, os, shutil

MERGE = {"Insular Oceania": "Oceania"}
MIN_COUNTRIES = 10          # only continents big enough to be a satisfying list
SECONDS = 60

# Curation — the corpus's wd:continent (P30) claims include a few HISTORICAL or
# defunct states and duplicates of a current country. For an enumeration drill
# every entry is shown in the reveal as "a country you should have named", so
# these must go. Dependent territories that are real, current, and commonly
# named (Greenland, Aruba, …) are kept — a forgiving "name as many" quiz includes
# them.
DROP_COUNTRIES = {
    "Emirate of Al Qawasim", "Emirate of Lengeh", "Maragheh Khanate",
    "Muscat and Oman",          # historical → Oman (already listed)
    "Pahlavi Iran",             # historical → Iran (already listed)
    "Kingdom of the Netherlands",  # → Netherlands (already listed)
    "England",                  # constituent country → United Kingdom (already listed)
}
RENAME_COUNTRIES = {
    "People's Republic of China": "China",
}

CORPUS = "../../assets/corpus.json"
ENRICH = "../../assets/enrich.json"
OUT = "../../assets/enumerate.json"
COPIES = [
    "../../TidbitsTrivia/Resources/enumerate.json",
    "../../android/app/src/main/assets/enumerate.json",
]


def pid(s):
    return "enum:" + hashlib.sha1(s.encode()).hexdigest()[:14]


def is_iso_code(a):
    """Short cryptic codes (cd, BJ, BEN, U.S.A) the matcher would lowercase
    into false positives — drop them, keep human-readable aliases."""
    bare = a.replace(".", "")
    if len(bare) <= 3 and bare.isalpha() and bare == bare.upper():
        return True              # all-caps 2-3 letter ISO code
    if len(a) == 2 and a.islower():
        return True              # bare 2-letter lowercase code
    return False


# Hardcoded canonical sets. Each entry: (canonical, [aliases]).
HARDCODED = [
    ("Name the 8 planets of the Solar System", "Science", [
        ("Mercury", []), ("Venus", []), ("Earth", []), ("Mars", []),
        ("Jupiter", []), ("Saturn", []), ("Uranus", []), ("Neptune", []),
    ], "https://en.wikipedia.org/wiki/Solar_System"),
    ("Name the 7 continents", "Geography", [
        ("Africa", []), ("Antarctica", []), ("Asia", []), ("Europe", []),
        ("North America", []), ("South America", []), ("Oceania", ["Australia"]),
    ], "https://en.wikipedia.org/wiki/Continent"),
    ("Name the 5 oceans", "Geography", [
        ("Pacific", ["Pacific Ocean"]), ("Atlantic", ["Atlantic Ocean"]),
        ("Indian", ["Indian Ocean"]), ("Southern", ["Southern Ocean", "Antarctic Ocean"]),
        ("Arctic", ["Arctic Ocean"]),
    ], "https://en.wikipedia.org/wiki/Ocean"),
    ("Name the 5 Great Lakes of North America", "Geography", [
        ("Superior", ["Lake Superior"]), ("Michigan", ["Lake Michigan"]),
        ("Huron", ["Lake Huron"]), ("Erie", ["Lake Erie"]), ("Ontario", ["Lake Ontario"]),
    ], "https://en.wikipedia.org/wiki/Great_Lakes"),
    ("Name the first 20 chemical elements (by atomic number)", "Science", [
        ("Hydrogen", ["H"]), ("Helium", ["He"]), ("Lithium", ["Li"]),
        ("Beryllium", ["Be"]), ("Boron", ["B"]), ("Carbon", ["C"]),
        ("Nitrogen", ["N"]), ("Oxygen", ["O"]), ("Fluorine", ["F"]),
        ("Neon", ["Ne"]), ("Sodium", ["Na"]), ("Magnesium", ["Mg"]),
        ("Aluminium", ["Al", "Aluminum"]), ("Silicon", ["Si"]),
        ("Phosphorus", ["P"]), ("Sulfur", ["S", "Sulphur"]), ("Chlorine", ["Cl"]),
        ("Argon", ["Ar"]), ("Potassium", ["K"]), ("Calcium", ["Ca"]),
    ], "https://en.wikipedia.org/wiki/Periodic_table"),
]


def main():
    qs = json.load(open(CORPUS))["questions"]
    enrich = json.load(open(ENRICH)).get("entities", {})

    by_cont, url_of = {}, {}
    seen_country = set()
    for q in qs:
        if not q[0].startswith("wd:continent:"):
            continue
        country, cont = q[7], q[2][q[3]]
        cont = MERGE.get(cont, cont)
        if country in DROP_COUNTRIES:
            continue
        country = RENAME_COUNTRIES.get(country, country)
        if country in seen_country:
            continue
        seen_country.add(country)
        by_cont.setdefault(cont, []).append(country)
        url_of[country] = q[8]

    out = []

    # 1. Continent -> countries puzzles.
    for cont in sorted(by_cont):
        countries = sorted(set(by_cont[cont]))
        if len(countries) < MIN_COUNTRIES:
            continue
        # original names that were renamed to a canonical, kept as accepted aliases
        rev_rename = {}
        for orig, canon in RENAME_COUNTRIES.items():
            rev_rename.setdefault(canon, []).append(orig)
        groups = []
        for c in countries:
            aliases = enrich.get(c.replace(" ", "_"), {}).get("aliases", [])
            aliases = [a for a in aliases if not is_iso_code(a)]
            aliases += rev_rename.get(c, [])
            # dedupe (case-insensitively) while preserving order; canonical first
            seen_a, group = set(), []
            for name in [c] + aliases:
                lk = name.lower()
                if lk not in seen_a:
                    seen_a.add(lk); group.append(name)
            groups.append(group)
        prompt = f"Name as many countries in {cont} as you can"
        out.append([pid(prompt), prompt, groups, "Geography", SECONDS,
                    f"https://en.wikipedia.org/wiki/{cont.replace(' ', '_')}"])

    # 2. Hardcoded canonical sets.
    for prompt, cat, entries, url in HARDCODED:
        groups = [[name] + aliases for name, aliases in entries]
        out.append([pid(prompt), prompt, groups, cat, SECONDS, url])

    payload = {"version": hashlib.sha1(json.dumps(out).encode()).hexdigest()[:12],
               "count": len(out), "questions": out}
    json.dump(payload, open(OUT, "w"), ensure_ascii=False)
    for dst in COPIES:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(OUT, dst)

    total_slots = sum(len(r[2]) for r in out)
    print(f"wrote {len(out)} enumeration puzzles, {total_slots} total answer slots")
    for r in out:
        print(f"  {r[1]} -> {len(r[2])} answers")


if __name__ == "__main__":
    main()
