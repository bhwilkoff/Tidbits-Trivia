"""Prove each gate rule catches the defect it names.

KIND-MISMATCH read 0 for an entire session while looking straight at a free
question, because the classifier under it typed a tsetse fly as a disease. The
rule was not disabled and its budget was not raised — it simply could not see.

A rule that has never been shown to FIRE is a rule nobody has tested. This plants
one known-bad row per rule into a copy of the real corpus, runs the real gate
against it, and asserts the rule reports at least one hit. Rules whose input is
not a single row — a corpus-wide RATE, or a signal from enrich.json — are listed
by name in COVERED_ELSEWHERE with what they would need, so the coverage gap is
visible rather than implied.

    python3 tools/corpus/test_quality_gate.py

Exits non-zero if any rule fails to notice its own planted defect.
"""
import collections
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"

# rule -> a row that must trip it. Row shape:
#   [id, prompt, options, correctIndex, category, difficulty, explanation, subject, ...]
PLANTED = {
    "ANSWER-IN-PROMPT": ["test:aip", "Which element is Helium?",
                         ["Helium", "Neon", "Argon", "Xenon"], 0, "science", 2,
                         "Helium: Chemical element.", "Helium"],
    "DUP-OPTION": ["test:dup", "Which of these is a noble gas?",
                   ["Neon", "Neon", "Iron", "Zinc"], 0, "science", 2,
                   "Neon: Chemical element.", "Neon"],
    # MACHINE looks for a Wikidata property WITH its colon, or a bare QID —
    # the first version of this plant used "P31" with no colon and reported the
    # rule BLIND when the rule was right and the test was wrong.
    "MACHINE-STEM": ["test:machine", "What is P31: of Helium?",
                     ["Gas", "Metal", "Liquid", "Plasma"], 0, "science", 2,
                     "Helium: Chemical element.", "Helium"],
    "PLACEHOLDER": ["test:placeholder", "Which country is TODO %@?",
                    ["France", "Spain", "Italy", "Greece"], 0, "geography", 2,
                    "France: Country in Europe.", "France"],
    "STUB-REVEAL": ["test:stub", "In what year was the test subject born?",
                    ["1901", "1902", "1903", "1904"], 0, "history", 2,
                    "Test Subject: 1901.", "Test Subject"],
    "DOUBLED-STEM": ["test:doubled", "In which country is Test Corp based based?",
                     ["France", "Spain", "Italy", "Greece"], 0, "business", 2,
                     "Test Corp: Company.", "Test Corp"],
    "TERSE-STEM": ["test:terse", "Most people of the four — which one?",
                   ["India", "China", "Peru", "Chad"], 1, "geography", 2,
                   "China: Country in Asia.", "China"],
    "LOWERCASE-PROMPT": ["test:lower", "helium is denoted by which symbol?",
                         ["He", "Ne", "Ar", "Xe"], 0, "science", 2,
                         "Helium: Chemical element.", "Helium"],
    "REVEAL-TYPOGRAPHY": ["test:typo", "Which state is this?",
                          ["Arkansas", "Nevada", "Kansas", "Oregon"], 0, "geography", 2,
                          "Arkansas: U.S. state. Arkansas ( , AR-kan-saw) is landlocked.",
                          "Arkansas"],
    "NUMBER-AGREEMENT": ["test:number", "In which country is the Andaman Islands?",
                         ["India", "Spain", "Italy", "Greece"], 0, "geography", 2,
                         "Andaman Islands: Archipelago.", "Andaman Islands"],
    # Index 9 is a TAGS ARRAY. A generated batch padded it with "" and shipped
    # 1,464 rows that every local check accepted and Android's CreateGoldenTest
    # threw on in CI, because it calls getJSONArray(9).
    "ROW-SCHEMA": ["test:schema", "Which of these is a test row?",
                   ["A", "B", "C", "D"], 0, "science", 2,
                   "A: A test subject.", "A", "", ""],
    "MISSING-ARTICLE": ["test:article", "On which continent is Peace River?",
                        ["North America", "Europe", "Asia", "Africa"], 0, "geography", 2,
                        "Peace River: River in Canada.", "Peace River"],
    # These six need subjects the classifier already knows, so they name REAL
    # ones. If a rename ever makes one untypeable the test goes BLIND and says
    # so, which is the point — a plant that quietly stops working is the same
    # failure as a rule that quietly stops seeing.
    "KIND-MISMATCH": ["test:kind", "Which of these is an island nation?",
                      ["Fiji", "Bob Kane", "Nauru", "Spain"], 0, "geography", 2,
                      "Fiji: Country in Oceania.", "Fiji"],
    "STEM-TYPE": ["test:stemtype", "In which country is American Psycho?",
                  ["France", "Spain", "Italy", "Greece"], 0, "screen", 2,
                  "American Psycho: Horror novel.", "American Psycho"],
    "PRESENT-TENSE-PAST": ["test:tense", "What is the capital of the Kingdom of Navarre?",
                           ["Pamplona", "Madrid", "Lisbon", "Paris"], 0, "history", 2,
                           "Kingdom of Navarre: Former kingdom.", "Kingdom of Navarre"],
    "CITY-LANGUAGE": ["test:citylang",
                      "Which of these is an official language of Thessaloniki?",
                      ["Greek", "Danish", "Polish", "Czech"], 0, "geography", 2,
                      "Thessaloniki: Second-largest city in Greece.", "Thessaloniki"],
    # Two plants: the nationality ADJECTIVE and the COUNTRY name. The second is
    # the shape found by playing — "served as Turkey's defense minister" over
    # Debs, Dean, Akar and Aquino — which the adjective-only pattern never saw.
    "NATIONALITY-FREE": [
        ["test:nat", "This Russian dancer is world famous — who?",
         ["Maya Plisetskaya", "Anne Rice", "Susan Sontag",
          "Coretta Scott King"], 0, "arts", 2,
         "Maya Plisetskaya: Russian ballerina.", "Maya Plisetskaya"],
        ["test:nat2", "Who served as Russia's most famous prima ballerina?",
         ["Maya Plisetskaya", "Anne Rice", "Susan Sontag",
          "Coretta Scott King"], 0, "arts", 2,
         "Maya Plisetskaya: Russian ballerina.", "Maya Plisetskaya"],
    ],
    "ERA-SPREAD": ["test:era", "Which of these people is best known?",
                   ["Bob Kane", "Pontius Pilate", "Anne Rice", "Susan Sontag"], 0,
                   "history", 2, "Bob Kane: American comic book artist.", "Bob Kane"],
}

# Shape-source rules. Each plants one row into the named file; the file's real
# rows are kept so THIN-COVERAGE stays satisfied.
PLANTED_SHAPES = {
    # Two plants, two branches. The first is caught by kind_map (a PERSON among
    # countries); the second only by the Wikidata type family, because kind_map
    # calls Amsterdam and Botswana both "place" and saw nothing wrong with 97
    # shipped rounds that put a city, an island or a volcano among three
    # countries.
    "ODD-ONE-KIND": ("oddoneout.json", [
        ["test:oddkind", "Which of these is the odd one out?",
         ["Fiji", "Nauru", "Spain", "Bob Kane"], 3, "geography", 2,
         "Bob Kane is a person among three countries.", "", ""],
        ["test:oddkind2", "Which of these is the odd one out?",
         ["Botswana", "Burkina Faso", "Amsterdam", "Burundi"], 2, "geography", 2,
         "Amsterdam is in Europe \u2014 the other three are all in Africa.",
         "Amsterdam", ""],
    ]),
    "UNANSWERABLE-TYPEIN": ("typeanswer.json",
                            ["test:typein", 'Who is this — "Swedish actress"?',
                             "Ingrid Bergman", [], "screen", 2,
                             "Ingrid Bergman: Swedish actress.", "Ingrid Bergman"]),
    "READ-OFF": ("match.json",
                 ["test:readoff", "Match each country to its currency.",
                  ["Singapore", "Japan", "Peru", "Chad"],
                  ["Singapore dollar", "Yen", "Sol", "Franc"], "geography",
                  "Singapore → Singapore dollar", "", ""]),
    "BROKEN-SHAPE": ("picture.json",
                     ["test:broken", "Who is this?",
                      ["A", "B", "C", "D"], 0, "screen", 2,
                      "A: Test.", "A", "", ""]),
}

# Rules whose trigger is not a single corpus row. Named so the coverage gap is
# visible rather than implied.
COVERED_ELSEWHERE = {
    # The four RATE rules cannot be tripped by one row by construction — that is
    # what makes them rate rules — and each was proven by hand when it was
    # written, with the measurement in its commit.
    "THIN-COVERAGE": "needs a mode x category the shape files cannot fill",
    "GOLDEN-STALE": "proven by hand 2026-08-02 (planted a missing id)",
    "CATEGORY-SKEW": "proven by hand 2026-08-02 (lowered the screen ceiling)",
    "SLIDER-FARMABLE": "rate over closest.json, proven by the pre-fix 61.7%",
    "NUMERIC-SORTED": "rate over all numeric sets, not one row",
    "PROMPT-REPETITION": "share of the whole corpus, not one row",
}


# --- rate rules -------------------------------------------------------------
# These cannot be tripped by one row against the REAL corpus, which is what I
# wrongly called "impossible by construction". They trip fine against a MINIMAL
# corpus where the planted rows dominate the rate. The assertion changes from
# "the gate otherwise passed" to "the target rule fired" — other rules failing on
# a 20-row corpus is expected and ignored.
RATE_CASES = {
    "NUMERIC-SORTED": "every numeric option set ascending",
    "PROMPT-REPETITION": "one prompt on a fifth of the corpus",
    "CATEGORY-SKEW": "screen far past its ceiling",
    "THIN-COVERAGE": "a category with no shape rows at all",
    "GOLDEN-STALE": "a golden id the corpus does not contain",
    "SLIDER-FARMABLE": "closest rows one fixed guess wins",
}


def _mini_row(i, prompt, opts, cat="screen"):
    return [f"mini:{i}", prompt, opts, 0, cat, 2, f"Thing {i}: A test subject.",
            f"Thing {i}", ""]


def rate_rule_fixture(tmpdir):
    """A 20-row corpus that trips every rate rule at once."""
    rows = []
    # NUMERIC-SORTED: ascending numeric sets, far past the 8% ceiling.
    for i in range(8):
        rows.append(_mini_row(i, f"Which year did thing {i} happen?",
                              ["1900", "1910", "1920", "1930"]))
    # PROMPT-REPETITION: one prompt over 1% of the corpus.
    for i in range(8, 12):
        rows.append(_mini_row(i, "Which of these four is the oldest?",
                              ["Alpha", "Beta", "Gamma", "Delta"]))
    # CATEGORY-SKEW: everything above is `screen`, so screen is ~100%.
    for i in range(12, 20):
        rows.append(_mini_row(i, f"Who made thing {i}?",
                              ["Ann", "Ben", "Cal", "Dee"]))
    (tmpdir / "corpus.json").write_text(
        '{"version":"test","count":%d,"questions":%s}'
        % (len(rows), json.dumps(rows, ensure_ascii=False)))

    # THIN-COVERAGE: an empty shape file has no category at all.
    for name in ("oddoneout.json", "match.json", "picture.json", "order.json",
                 "thisorthat.json", "typeanswer.json", "enumerate.json"):
        (tmpdir / name).write_text('{"version":"test","count":0,"questions":[]}')
    # SLIDER-FARMABLE: every answer inside one tolerance band of 1950.
    closest = [[f"closest:birth_year:T{i}", f"In what year was T{i} born?",
                1950 + (i % 3), 1900, 2020, 1, 40, "", "screen",
                f"T{i}: A test subject.", f"T{i}", ""] for i in range(20)]
    (tmpdir / "closest.json").write_text(
        '{"version":"test","count":%d,"questions":%s}'
        % (len(closest), json.dumps(closest, ensure_ascii=False)))
    # GOLDEN-STALE: a golden naming an id the mini corpus cannot contain.
    gdir = tmpdir / "_golden"
    gdir.mkdir()
    (gdir / "search.txt").write_text("Test Topic\tsrc:cloze:Not_In_This_Corpus\n")
    return gdir


def check_rate_rules():
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = pathlib.Path(tmp)
        for f in ASSETS.iterdir():
            if not (tmpdir / f.name).exists() and f.suffix == ".json":
                if f.name in ("enrich.json", "difficulty.json"):
                    (tmpdir / f.name).symlink_to(f)
        gdir = rate_rule_fixture(tmpdir)

        real_golden = ROOT / "tools" / "create" / "golden" / "search.txt"
        backup = real_golden.read_text() if real_golden.exists() else None
        try:
            if backup is not None:
                real_golden.write_text((gdir / "search.txt").read_text())
            env = dict(os.environ, TIDBITS_ASSETS=str(tmpdir))
            out = subprocess.run(
                [sys.executable, str(ROOT / "tools/corpus/quality_gate.py"), "--report"],
                capture_output=True, text=True, env=env).stdout
        finally:
            if backup is not None:
                real_golden.write_text(backup)

    seen = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1].isdigit():
            seen[parts[0]] = int(parts[1])
    return seen


def main():
    corpus = json.loads((ASSETS / "corpus.json").read_text())
    rows = corpus["questions"]
    width = max(len(r) for r in rows)

    # Pad to the corpus's OWN schema, not with "". Padding blindly is the very
    # defect ROW-SCHEMA exists to catch, and doing it here made every plant trip
    # that rule and drowned the one row that was supposed to.
    schema = []
    for i in range(width):
        types = collections.Counter(type(q[i]).__name__ for q in rows if len(q) > i)
        schema.append(types.most_common(1)[0][0])
    blank = {"list": [], "str": "", "int": 0, "float": 0.0, "NoneType": None}

    planted = []
    for name, row in PLANTED.items():
        # A rule may plant SEVERAL rows when it has more than one way to fire.
        # NATIONALITY-FREE reads both "this Turkish general" and "Turkey's
        # defense minister", and one plant would leave whichever branch it does
        # not use unprotected — which is how the country form came to be missed.
        for one in (row if isinstance(row[0], list) else [row]):
            r = list(one)
            while len(r) < width:
                r.append(blank.get(schema[len(r)], ""))
            # ...except the ROW-SCHEMA plant, which must violate it on purpose.
            if name == "ROW-SCHEMA":
                r[9] = ""
            planted.append(r)

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = pathlib.Path(tmp)
        shaped = {f for f, _ in PLANTED_SHAPES.values()}
        for f in ASSETS.iterdir():
            if f.name != "corpus.json" and f.name not in shaped:
                (tmpdir / f.name).symlink_to(f)
        for fname in shaped:
            d = json.loads((ASSETS / fname).read_text())
            extra = []
            for f, row in PLANTED_SHAPES.values():
                if f != fname:
                    continue
                extra += [list(x) for x in (row if isinstance(row[0], list) else [row])]
            srows = d["questions"] + extra
            b = json.dumps(srows, ensure_ascii=False, separators=(",", ":"))
            (tmpdir / fname).write_text(
                f'{{"version":"{d["version"]}","count":{len(srows)},"questions":{b}}}')
        body = json.dumps(rows + planted, ensure_ascii=False, separators=(",", ":"))
        (tmpdir / "corpus.json").write_text(
            f'{{"version":"{corpus["version"]}","count":{len(rows)+len(planted)},'
            f'"questions":{body}}}')

        env = dict(os.environ, TIDBITS_ASSETS=str(tmpdir))
        out = subprocess.run([sys.executable, str(ROOT / "tools/corpus/quality_gate.py"),
                              "--report"], capture_output=True, text=True, env=env).stdout

    found = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1].isdigit():
            found[parts[0]] = int(parts[1])

    failures = []
    print(f"{'rule':22}{'planted':>9}{'seen':>7}   status")
    for rule in sorted(set(PLANTED) | set(PLANTED_SHAPES)):
        n = found.get(rule)
        row = PLANTED.get(rule)
        if row is None:
            shaped = PLANTED_SHAPES.get(rule)
            row = shaped[1] if shaped else None
        count = len(row) if (row and isinstance(row[0], list)) else 1
        ok = n is not None and n >= count
        print(f"{rule:22}{count:>9}{n if n is not None else '-':>7}   "
              f"{'ok' if ok else 'BLIND'}")
        if not ok:
            failures.append(rule)

    rate_seen = check_rate_rules()
    print(f"\n{'rate rule':22}{'seen':>7}   status")
    for rule, what in sorted(RATE_CASES.items()):
        n = rate_seen.get(rule, 0)
        ok = n >= 1
        print(f"{rule:22}{n:>7}   {'ok' if ok else 'BLIND'}   ({what})")
        if not ok:
            failures.append(rule)

    print(f"\n{len(COVERED_ELSEWHERE)} rules need input this harness does not plant:")
    for rule, why in sorted(COVERED_ELSEWHERE.items()):
        print(f"   {rule:22} {why}")

    if failures:
        print(f"\nBLIND RULES: {failures}")
        print("A rule that cannot see its own planted defect is not protecting anything.")
        return 1
    print("\nevery planted defect was caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
