"""Is this question worth asking a room? — the Scope-1 playability audit.

The corpus already passes "factually correct". This tool measures the three
things the owner named on 2026-09-01 as the bar for promoting the app:

  INTEREST           — will most players recognise the subject AND the answer?
  COMPREHENSIBILITY  — does the question parse on one reading, with no missing
                       context and no second defensible answer?
  NO REPELLENTS      — nothing that makes a player put the phone down.

Each check is named and runs independently, because they have very different
false-positive risks. `--write` only ever TOMBSTONES; nothing here rewrites a
row, because the two most expensive mistakes on this corpus were both bulk
rewrites that were confidently wrong (`detector-that-fires-on-quality`,
`randomness-inside-selection`). Read the hits, then write.

    python3 tools/corpus/audit_playability.py --check all
    python3 tools/corpus/audit_playability.py --check bare-description --limit 40
    python3 tools/corpus/audit_playability.py --check bare-description --write
"""
import argparse
import json
import random
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "TidbitsTrivia/Resources/corpus.sqlite"
SOURCE = ROOT / "tools/corpus/corpus_source.sqlite"
TOMBSTONES = ROOT / "tools/corpus/tombstones.json"


class Row:
    __slots__ = ("id", "prompt", "opts", "ci", "cat", "diff", "expl", "src", "tmpl")

    def __init__(self, t):
        (self.id, self.prompt, o0, o1, o2, o3, self.ci,
         self.cat, self.diff, self.expl, self.src, self.tmpl) = t
        self.opts = [o0, o1, o2, o3]

    @property
    def answer(self) -> str:
        return self.opts[self.ci] if 0 <= self.ci < 4 and self.opts[self.ci] else ""

    def text(self) -> str:
        return " ".join(x for x in [self.prompt, self.expl, *self.opts] if x)


def load(db) -> list[Row]:
    return [Row(t) for t in db.execute(
        """select id, prompt, option0, option1, option2, option3, correct_index,
                  category_id, difficulty, explanation, source_title, template_id
           from questions""")]


# ---------------------------------------------------------------- checks

BARE_DESCRIPTION = re.compile(r'^(?:Who|What) is this\s+[—-]\s+[“"]')


def check_bare_description(rows, _ctx):
    """A raw Wikidata description used as the entire clue.

    "Who is this — 'British actor (born 1977)'?" is unanswerable by design: the
    clue carries no fact, only a category, so the only way to score is to already
    know which of four names happens to be a British actor born in 1977. The
    same generator also produced the corpus's most repellent prompts, because a
    bare description passes straight through whatever the article is about.
    """
    return [r for r in rows if BARE_DESCRIPTION.match(r.prompt or "")]


# Deliberately narrow and concrete, and matched against the SUBJECT of the
# question only (its answer and its source article), never the whole blob.
#
# The first version of this list matched anywhere in prompt+explanation+options
# and returned 869 rows that were overwhelmingly the corpus's BEST questions:
# "Who wrote The Murder of Roger Ackroyd?", "Who composed the score for The
# Texas Chainsaw Massacre?", the platypus cloaca question, and an ANKLE question
# flagged as genitalia. That is `detector-that-fires-on-quality` exactly. A
# repellent question is one whose SUBJECT is the repellent thing; a question
# about a novel that has "murder" in its title is a trivia question about a novel.
REPELLENT_PATTERNS = [
    (r"child (?:rape|sexual abuse|pornograph|molest)", "child sexual abuse"),
    (r"\brape\b|gang[- ]rape|sexual assault|sexual abuse", "sexual violence"),
    (r"incest|pedophil|paedophil|child marriage", "sexual abuse"),
    (r"\bgenital|\bpenis\b|\bvagina\b|\btesticl|\bhymen\b|\bclitor|\bscrotum\b|\bfellatio\b|\bmasturbat",
     "genitalia / sex act"),
    (r"\bsuicide\b|self-immolat|self-harm", "suicide"),
    (r"\bmassacre\b|\bgenocide\b|ethnic cleansing|\bpogrom\b|\blynching\b", "mass atrocity"),
    (r"terror attack|terrorist attack|suicide bombing|school shooting|mass shooting|\bbombing of\b",
     "terror / shooting"),
    (r"concentration camp|extermination camp|death camp", "camps"),
    (r"female genital mutilation|honou?r killing|forced sterilis", "gender violence"),
    (r"ero guro|\bhentai\b|pornograph|\bporn\b|\bbrothel\b|prostitut", "pornography / sex trade"),
    (r"murder victim|murder of |serial killer|dismember|\bcannibal", "named-victim homicide"),
    (r"\bslur\b|racial slur|\bnigg|\bswastika\b|neo-nazi|far-right", "slur / extremism"),
]
REPELLENT = [(re.compile(p, re.I), why) for p, why in REPELLENT_PATTERNS]

# Subjects whose NAME contains a repellent word but which are creative works,
# not the thing itself. "The Murder of Roger Ackroyd" is an Agatha Christie
# novel; "The Texas Chain Saw Massacre" is a Tobe Hooper film; "The Rape of
# Proserpina" is a Bernini sculpture. A title suffix alone missed all three,
# so the article's own one-line description is consulted as well.
WORK_MARKER = re.compile(
    r"\((?:\d{4} )?(?:film|video game|novel|album|song|TV series|manga|anime|book|play|band)\b|"
    r"\b(?:film|novel|album|song|series|manga|opera|musical)\)", re.I)
WORK_DESCRIPTION = re.compile(
    r"\b(?:film|movie|novel|book|album|song|single|painting|sculpture|statue|video game|TV series|television series|manga|anime|comic|opera|musical|play|poem|band|episode|franchise|artwork)\b", re.I)


# Read in full on 2026-09-01, all 94 hits. These subjects stay: they are taught
# everywhere, carry no live dispute, and are standard quiz fare — removing them
# would be squeamishness rather than the owner's "would make people stop playing"
# bar. Everything else on the list is a mass-casualty atrocity, a named private
# individual's killing, a suicide, anatomy-as-quiz, or the porn industry.
REPELLENT_KEEP = {
    "Boston Massacre",
    "St. Bartholomew's Day massacre",
    "Saint Valentine's Day Massacre",
}
# "Clitoria ternatea" is the butterfly-pea FLOWER — a good botany question that
# the genitalia pattern hit on its Linnaean name.
REPELLENT_KEEP_PREFIX = ("Clitoria ",)


def check_repellent(rows, _ctx):
    """Material a host cannot read out to a bar, or that makes a player quit.

    This is NOT a squeamishness filter on history — the Second World War, the
    Titanic and the French Revolution all stay. It screens for the specific
    thing the owner named: a topic that stops the game dead. Every hit carries
    the pattern that fired so the list can be read and argued with.
    """
    out = []
    descriptions = _ctx or {}
    for r in rows:
        subject = f"{r.src or ''} {r.answer}"
        if (r.src or "") in REPELLENT_KEEP or r.answer in REPELLENT_KEEP:
            continue
        if (r.src or "").startswith(REPELLENT_KEEP_PREFIX):
            continue
        if WORK_MARKER.search(subject):
            continue
        if WORK_DESCRIPTION.search(descriptions.get(r.src, "")):
            continue
        for rx, why in REPELLENT:
            if rx.search(subject):
                out.append((r, why))
                break
    return out


# A given name with no disambiguator, where the question turns on WHICH one.
AMBIG_NAMES = ("David", "John", "Mary", "James", "Paul", "Peter", "George",
               "Charles", "Henry", "Louis", "Philip", "Richard", "Thomas",
               "William", "Alexander", "Constantine", "Frederick", "Joseph")
AMBIG = re.compile(r"\b(?:was|did|is|does)\s+(" + "|".join(AMBIG_NAMES) + r")\s+(?:born|die|reign|rule|become)\b")


def check_ambiguous_subject(rows, _ctx):
    """A bare given name where the answer depends on which person is meant.

    "In what year did David die?" appeared in the Mac cockpit's demo round. The
    King David reading and the several dozen other Davids in the corpus are all
    defensible, so the question has no single answer a player can reason to.
    """
    return [r for r in rows if AMBIG.search(r.prompt or "")]


def check_self_answering(rows, _ctx):
    """The answer is printed inside its own prompt.

    Only the `biz` templates are reported, and deliberately so. There the shape
    is structural — the prompt is a company name and the answer is its country
    or industry, so "Icelandair is headquartered in which country?" hands the
    answer over. Applying the same prefix test to prose clues produced four
    false positives out of fourteen ("drug trafficking" matching the film
    *Traffic*, "chocolaterie" matching *Chocolat*, "uploaded" matching *Upload*,
    "Jessica" matching the rapper *Jessi*), so prose is left to a reader.
    """
    out = []
    for r in rows:
        if not (r.tmpl or "").startswith("biz"):
            continue
        ans = (r.answer or "").strip()
        core = re.sub(r"\s*\([^)]*\)\s*$", "", ans).strip()
        if len(core) < 5:
            continue
        # Case-SENSITIVE, leading boundary only: "Australia" must count inside
        # "Australian National University", which answers itself.
        if re.search(r"\b" + re.escape(core), r.prompt or ""):
            out.append(r)
    return out


CHECKS = {
    "bare-description": (check_bare_description,
                         "CORPUS-BARE-DESC: a raw Wikidata description used as the whole clue — unanswerable"),
    "repellent": (check_repellent,
                  "CORPUS-REPELLENT: a topic a host cannot read out to a room"),
    "ambiguous-subject": (check_ambiguous_subject,
                          "CORPUS-AMBIGUOUS: a bare given name with several equally valid referents"),
    "self-answering": (check_self_answering,
                       "CORPUS-SELF-ANSWERING: the answer is printed inside its own prompt"),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", default="all",
                    help="comma-separated: " + ",".join(CHECKS) + ", or all")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--write", action="store_true", help="tombstone the hits of the named checks")
    ap.add_argument("--seed", type=int, default=11)
    a = ap.parse_args()

    if not CORPUS.exists():
        print(f"missing corpus: {CORPUS}", file=sys.stderr)
        return 2
    names = list(CHECKS) if a.check == "all" else [c.strip() for c in a.check.split(",")]
    unknown = [n for n in names if n not in CHECKS]
    if unknown:
        print(f"unknown check(s): {unknown}. known: {list(CHECKS)}", file=sys.stderr)
        return 2

    db = sqlite3.connect(CORPUS)
    rows = load(db)
    descriptions = {}
    if SOURCE.exists():
        src = sqlite3.connect(SOURCE)
        descriptions = {t: d or "" for t, d in src.execute("select title, description from prose")}
    # tombstones.json is keyed by SHAPE ({"corpus": {...}, "match": {...}}) and
    # `genguard` reads it that way; a flat write at the top level silently
    # corrupts every shape's guard.
    doc = json.loads(TOMBSTONES.read_text()) if TOMBSTONES.exists() else {}
    tomb = doc.setdefault("corpus", {})
    live = [r for r in rows if r.id not in tomb]
    print(f"corpus rows: {len(rows):,}   already tombstoned: {len(rows) - len(live):,}   live: {len(live):,}\n")

    random.seed(a.seed)
    to_write: dict[str, str] = {}
    for name in names:
        fn, reason = CHECKS[name]
        hits = fn(live, descriptions)
        # Some checks return (row, why) pairs.
        pairs = [(h, None) if isinstance(h, Row) else h for h in hits]
        print(f"=== {name}: {len(pairs):,} rows ({100 * len(pairs) / max(len(live), 1):.2f}% of live) ===")
        sample = random.sample(pairs, min(a.limit, len(pairs)))
        for r, why in sample:
            tag = f" [{why}]" if why else ""
            print(f"  {r.id}{tag}")
            print(f"     {r.prompt[:120]}")
            print(f"     -> {r.answer[:70]}   ({r.cat}, {r.tmpl})")
        print()
        for r, why in pairs:
            to_write[r.id] = reason + (f" ({why})" if why else "")

    if a.write:
        added = 0
        for qid, why in to_write.items():
            if qid not in tomb:
                tomb[qid] = why
                added += 1
        doc["corpus"] = tomb
        TOMBSTONES.write_text(json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        print(f"tombstoned {added:,} new rows -> {TOMBSTONES.relative_to(ROOT)}")
        print("re-run the corpus build so every mirror drops them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
