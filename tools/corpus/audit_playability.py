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
    descriptions = (_ctx or {}).get("descriptions", {})
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


# Wikidata P31 classes whose members are NOT "founded". A country has no single
# founding date a player can reason to — unification, independence, the current
# republic and the current constitution are all defensible answers — and asking
# "In what year was Italy founded?" is both ill-posed and politically loaded.
#
# CITIES are deliberately NOT here: a city genuinely is founded, and "In what year
# was Bucharest founded?" is a normal quiz question.
NOT_FOUNDED_CLASSES = {
    "Q3624078": "sovereign state",
    "Q6256": "country",
    "Q5": "person",
    "Q23442": "island",
    "Q8502": "mountain",
    "Q4022": "river",
    "Q23397": "lake",
    "Q7365": "star",
    "Q634": "planet",
}
# Q3024240 "historical country" is DELIBERATELY absent. Reading the hits showed it
# sweeps in dynasties, empires and caliphates — "In what year was the Ming dynasty
# founded? -> 1368", "Umayyad Caliphate -> 661", "Achaemenid Empire -> 550 BC" —
# all of which ARE conventionally founded and have textbook dates. The class that
# is actually broken is the MODERN sovereign state, where "founded" silently means
# independence, unification, or the current constitution depending on the country.
# Q1250464 "realm" is out for the same reason: it caught the Chola and Chalukya
# DYNASTIES, which are founded in the ordinary sense.
# The construction that matters is PASSIVE — the subject is the thing being
# founded ("In what year was Italy founded?"). Active voice is ordinary English
# and ordinary trivia: "This businessman co-founded a ride-hailing company" is a
# good question about Travis Kalanick, and the first version of this check
# flagged 1,619 rows that were overwhelmingly exactly that.
FOUNDED_PASSIVE = re.compile(
    r"^In what year was (?:the )?(.+?) founded\?$"
    r"|^(?:The )?(.+?) was founded in (?:which|what) year\?$"
    r"|^(?:In )?(?:which|what) year was (?:the )?(.+?) founded\?$", re.I)
FOUNDED_COMPARISON = re.compile(r"\bfounded (?:earliest|first|last|most recently)\b", re.I)


def check_founded_misuse(rows, ctx):
    """"Founded" applied to something that was not founded.

    The owner named this class directly: *"there should be no 'founded' questions
    for things that weren't founded"*. An earlier pass fixed characters (created)
    and bands (formed) but never looked at COUNTRIES, which is where the worst of
    it lives: "In what year was Italy founded?", "In what year was India founded?"

    These are not a wording problem with a rewrite available — a country has no
    single founding date a player can reason to (unification, independence, the
    current republic and the current constitution are all defensible) — so they go
    rather than getting a new verb.

    Cities are excluded on purpose: a city genuinely IS founded.
    """
    classes = (ctx or {}).get("p31", {})

    def not_founded(title):
        for cl in (classes.get(title, "") or "").split(","):
            if cl in NOT_FOUNDED_CLASSES:
                return NOT_FOUNDED_CLASSES[cl]
        return None

    out = []
    for r in rows:
        prompt = r.prompt or ""
        why = None
        if FOUNDED_PASSIVE.match(prompt):
            # The subject is the thing being founded.
            why = not_founded(r.src or "")
        elif FOUNDED_COMPARISON.search(prompt):
            # A comparison round claims one OPTION was founded earliest; the claim
            # is only as sound as what is being compared.
            why = not_founded(r.answer)
        if why:
            out.append((r, why))
    return out


# --- low-interest shapes (the notability pass) -------------------------------
#
# A single global notability floor is the WRONG instrument, and the numbers say so:
# the corpus median subject sits at qrank ~1.0M while Marta Fascina — the question
# that started this whole scope — sits at 1.66M, ABOVE the median. What actually
# predicts a dead question is the SHAPE crossed with the subject's fame, and each
# shape has its own answer. Every floor below was set by reading the rows on both
# sides of it, never by picking a percentile.
SHAPE_HEIGHT = re.compile(r"^About how tall is .+\?$")
SHAPE_ELEVATION = re.compile(r"^Approximately what is the elevation of .+\?$")
SHAPE_BORN_DIED = re.compile(r"^In what year (?:was|did) .+ (?:born|die)\?$")
SHAPE_AREA = re.compile(r"^Roughly how large is .+ by area\?$")

# Mountains keep their elevation question; it is the one subject for which
# "how high is it" is the actual famous fact.
MOUNTAIN_CLASSES = {"Q8502", "Q54050", "Q207326", "Q1437459"}

BORN_DIED_FLOOR = 3_000_000
AREA_FLOOR = 5_000_000


def check_low_interest_shape(rows, ctx):
    """Question shapes that no pub room can play, by shape and by subject fame.

    - HEIGHT is removed outright. At the very top of the fame distribution the
      questions are "About how tall is Lionel Messi?" (1.69 m) and "About how tall
      is Michael Jordan?" (1.98 m) — an unguessable coin-flip between four
      centimetre-apart options. If the shape is dead for Messi it is dead.
    - ELEVATION is removed except for mountains. "Approximately what is the
      elevation of Canada? -> 487 m" is a country's MEAN elevation, which is not a
      fact anyone holds.
    - BORN/DIED and AREA get fame floors, read at the boundary: below 3M the names
      are Bruno Fernandes and Alba Baptista; above it they are Ben Stiller and
      Ethan Hawke. Below 5M the areas are Liverpool and Riyadh; above it they are
      Algeria and Cambodia, which is the only case where "how large by area" works.

    RELEASED / FOUNDED deliberately get NO floor. The boundary read cut *Before
    Sunrise*, *Point Break*, *Kung Fu Hustle* and "In what year was the YMCA
    founded?" while keeping *Terrifier 2* — so qrank does not discriminate quality
    for that shape, and applying a floor there would have destroyed ~970 good
    questions on a metric that does not measure what it looked like it measured.
    """
    rank = (ctx or {}).get("qrank", {})
    classes = (ctx or {}).get("p31", {})
    out = []
    for r in rows:
        prompt = r.prompt or ""
        fame = rank.get(r.src or "", 0)
        if SHAPE_HEIGHT.match(prompt):
            out.append((r, "a person's height in metres"))
        elif SHAPE_ELEVATION.match(prompt):
            cls = set((classes.get(r.src or "", "") or "").split(","))
            if not (cls & MOUNTAIN_CLASSES):
                out.append((r, "the mean elevation of a place"))
        elif SHAPE_BORN_DIED.match(prompt) and fame < BORN_DIED_FLOOR:
            out.append((r, f"birth/death year of a subject below the recognition floor ({fame:,})"))
        elif SHAPE_AREA.match(prompt) and fame < AREA_FLOOR:
            out.append((r, f"area of a place below the recognition floor ({fame:,})"))
    return out


# Wikidata classes for things that do not have a birth or a founding date in any
# sense a player can reason about.
FICTIONAL_CLASSES = {
    "Q15632617",   # fictional human
    "Q95074",      # fictional character
    "Q3658341",    # literary character
    "Q15773347",   # film character
    "Q15632618",   # fictional organism
    "Q1114461",    # comics character
    "Q97498056",   # animated character
}
WIKIMEDIA_LIST = "Q13406463"
BIRTH_OR_FOUNDING = re.compile(r"\b(born|founded|established|birth)\b", re.I)


def check_fictional_chronology(rows, ctx):
    """A chronology question about when a FICTIONAL character was born or founded.

    "Which of these people was born first? — Scrooge McDuck / Punisher / Cedric
    Diggory / Voldemort". A character has a creation date, not a birth date, and
    whatever Wikidata carries is in-universe canon no player can reason from. An
    earlier pass fixed the wording for single-subject rows (characters get
    "created", bands get "formed") but never looked at the COMPARISON template,
    where the whole question is the chronology.

    Scoped to `chron`. In a `src` prose clue a fictional option is an ordinary
    distractor, and the KIND-MISMATCH gate already covers those.
    """
    classes = (ctx or {}).get("p31", {})
    out = []
    for r in rows:
        if r.tmpl != "chron" or not BIRTH_OR_FOUNDING.search(r.prompt or ""):
            continue
        opts = [o for o in r.opts if o]
        fictional = [o for o in opts
                     if set((classes.get(o, "") or "").split(",")) & FICTIONAL_CLASSES]
        if fictional:
            out.append((r, f"{len(fictional)} of {len(opts)} options are fictional characters"))
    return out


def check_list_article_option(rows, ctx):
    """A Wikimedia LIST ARTICLE offered as an answer option.

    "Which one below is the oldest? — War and Peace / Rocky / James Bond films /
    List of Marvel Cinematic Universe films". A list article is a page, not a
    thing with an age, so the option cannot be reasoned about at all.
    """
    classes = (ctx or {}).get("p31", {})
    out = []
    for r in rows:
        bad = [o for o in r.opts
               if o and WIKIMEDIA_LIST in set((classes.get(o, "") or "").split(","))]
        if bad:
            out.append((r, f"list article as an option: {bad[0]}"))
    return out


SUP_PROP = re.compile(r"^sup:(P\d+):")


def check_superlative_wrong(rows, ctx):
    """A superlative question whose claimed answer is not the extreme.

    "Which of these covers the most land? — New York City / London / ..." claims
    New York City (1,213 km2) over London (1,572 km2). A player who answers
    correctly is marked WRONG, which is the worst thing a quiz can do.

    Checked against the source's own numbers, comparing only within a single unit.
    A first pass ignored units and reported 40 hits including "Machu Picchu 32,500"
    beating "Sequoia National Park 1,635" — hectares against square kilometres.
    Reading them is also what showed that some rows are broken the OTHER way: the
    source value itself is wrong (the Great Barrier Reef at 34.9 million km2). Both
    make the question unplayable, so both go.
    """
    numbers = (ctx or {}).get("numbers", {})
    out = []
    for r in rows:
        m = SUP_PROP.match(r.id or "")
        if not m:
            continue
        prop = m.group(1)
        opts = [o for o in r.opts if o]
        vals = [(o, numbers.get(o, {}).get(prop)) for o in opts]
        if len(vals) < 4 or any(v is None for _, v in vals):
            continue
        if len({v[1] for _, v in vals}) > 1:   # mixed units — not comparable
            continue
        nums = {o: v[0] for o, v in vals}
        top = max(nums.values())
        claimed = nums.get(r.answer)
        if claimed is None or claimed == top:
            continue
        winner = next(o for o, v in nums.items() if v == top)
        out.append((r, f"claims {r.answer} but {winner} is the extreme"))
    return out


CHECKS = {
    "bare-description": (check_bare_description,
                         "CORPUS-BARE-DESC: a raw Wikidata description used as the whole clue — unanswerable"),
    "repellent": (check_repellent,
                  "CORPUS-REPELLENT: a topic a host cannot read out to a room"),
    "ambiguous-subject": (check_ambiguous_subject,
                          "CORPUS-AMBIGUOUS: a bare given name with several equally valid referents"),
    "low-interest-shape": (check_low_interest_shape,
                           "CORPUS-LOW-INTEREST: a question shape no room can play, or a subject below the recognition floor"),
    "fictional-chronology": (check_fictional_chronology,
                             "CORPUS-FICTIONAL-CHRONOLOGY: asks when a fictional character was born or founded — no answer a player can reason to"),
    "list-article-option": (check_list_article_option,
                            "CORPUS-LIST-ARTICLE: a Wikimedia list article offered as an answer option"),
    "superlative-wrong": (check_superlative_wrong,
                          "CORPUS-SUPERLATIVE-WRONG: the claimed answer is not the extreme — a correct answer is marked wrong"),
    "founded-misuse": (check_founded_misuse,
                       "CORPUS-FOUNDED-MISUSE: \"founded\" applied to something that was never founded — no single defensible answer"),
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
    descriptions, p31, qrank, numbers = {}, {}, {}, {}
    if SOURCE.exists():
        src = sqlite3.connect(SOURCE)
        descriptions = {t: d or "" for t, d in src.execute("select title, description from prose")}
        p31 = {t: c or "" for t, c in src.execute("select title, p31 from subject")}
        qrank = {t: q or 0 for t, q in src.execute("select title, qrank from subject")}
        titles = dict(src.execute("select qid, title from subject"))
        numbers = {}
        for qid, prop, val, unit in src.execute(
                "select qid, prop, value, unit from fact where value is not null"):
            t = titles.get(qid)
            if t:
                numbers.setdefault(t, {})[prop] = (val, unit or "")
    ctx = {"descriptions": descriptions, "p31": p31, "qrank": qrank, "numbers": numbers}
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
        hits = fn(live, ctx)
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
