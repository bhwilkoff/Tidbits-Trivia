"""Prove each gate rule catches the defect it names.

KIND-MISMATCH read 0 for an entire session while looking straight at a free
question, because the classifier under it typed a tsetse fly as a disease. The
rule was not disabled and its budget was not raised — it simply could not see.

A rule that has never been shown to FIRE is a rule nobody has tested. This plants
one known-bad row per rule into a copy of the real corpus, runs the real gate
against it, and asserts the rule reports at least one hit. Rules whose input is
not a corpus row (THIN-COVERAGE, BROKEN-SHAPE, GOLDEN-STALE, CATEGORY-SKEW,
SLIDER-FARMABLE, ODD-ONE-KIND, UNANSWERABLE-TYPEIN, READ-OFF) are listed as
covered elsewhere rather than silently skipped — see COVERED_ELSEWHERE.

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
}

# Rules whose trigger is not a single corpus row. Named so the coverage gap is
# visible rather than implied.
COVERED_ELSEWHERE = {
    "THIN-COVERAGE": "needs a mode x category the shape files cannot fill",
    "BROKEN-SHAPE": "needs a malformed shape-source row",
    "ODD-ONE-KIND": "needs an oddoneout.json row",
    "UNANSWERABLE-TYPEIN": "needs a typeanswer.json row",
    "READ-OFF": "needs a match.json row",
    "GOLDEN-STALE": "proven by hand 2026-08-02 (planted a missing id)",
    "CATEGORY-SKEW": "proven by hand 2026-08-02 (lowered the screen ceiling)",
    "SLIDER-FARMABLE": "rate over closest.json, proven by the pre-fix 61.7%",
    "NUMERIC-SORTED": "rate over all numeric sets, not one row",
    "PROMPT-REPETITION": "share of the whole corpus, not one row",
    "ERA-SPREAD": "needs enrich.json birth years for the planted subject",
    "KIND-MISMATCH": "needs the planted subjects to carry descriptions",
    "STEM-TYPE": "needs a subject description the classifier can read",
    "CITY-LANGUAGE": "needs a city description and a country language set",
    "NATIONALITY-FREE": "needs four described subjects with nationalities",
    "PRESENT-TENSE-PAST": "needs Wikidata's historical-country class",
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
        for f in ASSETS.iterdir():
            if f.name != "corpus.json":
                (tmpdir / f.name).symlink_to(f)
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
    for rule in sorted(PLANTED):
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
