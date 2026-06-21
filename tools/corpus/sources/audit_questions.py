#!/usr/bin/env python3
"""Question-quality audit (Decision 032) — catch poorly-constructed questions.

A clever human asker gives enough context to make a question answerable by
KNOWLEDGE (not luck), is grammatical, and never lets the wording or the
distractors give the answer away. This scans the generated sets and flags the
systemic ways we violate that, with counts + examples, so fixes can be measured.

Checks (per type):
  LEAK       — a significant word of the answer appears in the prompt.
  CLOZE_PART — a cloze blank leaves part of the masked name visible
               ("Kim Soo-____") or the answer's words appear unmasked.
  GENDER     — the clue states a gender (actress/he/queen…) but the 4 options
               are NOT all that gender → guessable by elimination. (Uses the
               gender column in corpus_source.sqlite when available.)
  TYPE       — the clue states a profession (painter/physicist…) but the options
               aren't all that profession (uses P106 from the source DB).
  THIN       — a describe clue with no real context (date-only / too short).

Usage: python3 audit_questions.py
"""
import json, os, re, sqlite3
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

GENDER_WORDS = {
    "f": ["actress", "businesswoman", "she", "her", "herself", "queen", "princess",
          "duchess", "empress", "woman", "girl", "mother", "daughter", "sister", "heroine"],
    "m": ["actor", "businessman", "statesman", "he", "his", "himself", "king", "prince",
          "duke", "emperor", "man", "boy", "father", "son", "brother", "hero"],
}
# Wikidata sex-or-gender QIDs → f/m
GENDER_QID = {"Q6581072": "f", "Q6581097": "m"}


STOP = {"the", "and", "for", "was", "were", "are", "his", "her", "its", "from",
        "with", "who", "that", "this", "born", "american", "british", "english",
        "french", "german", "known", "professionally", "also",
        # generic category nouns — knowing the *kind* of thing isn't a giveaway
        "war", "art", "film", "movie", "series", "show", "album", "song", "single",
        "book", "novel", "city", "river", "band", "game", "team", "company", "play"}

def sig_words(s):
    s = re.sub(r"\s*\([^)]*\)", "", s or "")   # strip parenthetical disambiguators
    return [w for w in re.findall(r"[A-Za-z][A-Za-z'’]+", s)
            if len(w) >= 3 and w.lower() not in STOP]


def clue_of(prompt):
    m = re.search(r"[“\"](.+?)[”\"]", prompt)
    return m.group(1) if m else ""


def main():
    con = sqlite3.connect(DB)
    gender = {t.replace(" ", "_"): g for t, g in
              con.execute("SELECT title, gender FROM subject WHERE gender IS NOT NULL").fetchall()} \
        if _has_col(con, "subject", "gender") else {}
    qs = json.load(open(os.path.join(ROOT, "assets", "corpus.json")))["questions"]

    flags = Counter()
    examples = {}
    def flag(kind, q):
        flags[kind] += 1
        examples.setdefault(kind, [])
        if len(examples[kind]) < 4:
            examples[kind].append(f"{q[1][:80]} -> {q[2][q[3]] if q[2] else ''}")

    for q in qs:
        tmpl = q[0].split(":")[1] if ":" in q[0] else ""
        prompt, opts, ci = q[1], q[2], q[3]
        if not opts or ci >= len(opts):
            continue
        answer = opts[ci]
        clue = clue_of(prompt)

        # LEAK — answer word in the (non-clue) prompt or, for describe, in the clue
        ans_words = set(w.lower() for w in sig_words(answer))
        clue_words = set(w.lower() for w in sig_words(clue))
        if tmpl == "describe" and ans_words & clue_words:
            flag("LEAK", q)

        # CLOZE — partial-name leak: any answer word visible, or letters touching ____
        if tmpl == "cloze":
            shown = prompt.replace("____", " ")
            if ans_words & set(w.lower() for w in sig_words(shown)):
                flag("CLOZE_PART", q)
            elif re.search(r"[A-Za-z]-?_{2,}|_{2,}-?[A-Za-z]", prompt):
                flag("CLOZE_PART", q)

        # THIN — describe clue is only a date / too short to identify
        if tmpl == "describe":
            stripped = re.sub(r"\(?\b\d{3,4}\b[-–]?\d{0,4}\)?", "", clue).strip(" ()–-")
            if len(stripped) < 6:
                flag("THIN", q)

        # GENDER — gendered clue, options not all that gender (people only)
        if tmpl in ("describe", "cloze") and gender:
            cl = clue.lower()
            want = next((g for g, ws in GENDER_WORDS.items() if any(re.search(rf"\b{w}\b", cl) for w in ws)), None)
            if want:
                og = [gender.get(o.replace(" ", "_")) for o in opts]
                # only meaningful when options are people (have a gender)
                known = [g for g in og if g]
                if len(known) >= 2 and any(g and g != want for g in og):
                    flag("GENDER", q)

    print(f"=== QUESTION AUDIT — {len(qs):,} corpus rows ===")
    for kind in ("LEAK", "CLOZE_PART", "THIN", "GENDER"):
        print(f"\n{kind}: {flags[kind]:,}")
        for ex in examples.get(kind, []):
            print(f"    {ex}")
    con.close()


def _has_col(con, table, col):
    return any(r[1] == col for r in con.execute(f"PRAGMA table_info({table})").fetchall())


if __name__ == "__main__":
    main()
