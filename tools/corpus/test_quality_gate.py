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
    "NATIONALITY-FREE": ["test:nat", "This Russian dancer is world famous — who?",
                         ["Maya Plisetskaya", "Anne Rice", "Susan Sontag",
                          "Coretta Scott King"], 0, "arts", 2,
                         "Maya Plisetskaya: Russian ballerina.", "Maya Plisetskaya"],
    "ERA-SPREAD": ["test:era", "Which of these people is best known?",
                   ["Bob Kane", "Pontius Pilate", "Anne Rice", "Susan Sontag"], 0,
                   "history", 2, "Bob Kane: American comic book artist.", "Bob Kane"],
}

# Shape-source rules. Each plants one row into the named file; the file's real
# rows are kept so THIN-COVERAGE stays satisfied.
PLANTED_SHAPES = {
    "ODD-ONE-KIND": ("oddoneout.json",
                     ["test:oddkind", "Which of these is the odd one out?",
                      ["Fiji", "Nauru", "Spain", "Bob Kane"], 3, "geography", 2,
                      "Bob Kane is a person among three countries.", "", ""]),
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


def main():
    corpus = json.loads((ASSETS / "corpus.json").read_text())
    rows = corpus["questions"]
    width = max(len(r) for r in rows)

    planted = []
    for row in PLANTED.values():
        r = list(row) + [""] * (width - len(row))
        planted.append(r)

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = pathlib.Path(tmp)
        shaped = {f for f, _ in PLANTED_SHAPES.values()}
        for f in ASSETS.iterdir():
            if f.name != "corpus.json" and f.name not in shaped:
                (tmpdir / f.name).symlink_to(f)
        for fname in shaped:
            d = json.loads((ASSETS / fname).read_text())
            extra = [list(row) for f, row in PLANTED_SHAPES.values() if f == fname]
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
        ok = n is not None and n >= 1
        print(f"{rule:22}{1:>9}{n if n is not None else '-':>7}   {'ok' if ok else 'BLIND'}")
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
