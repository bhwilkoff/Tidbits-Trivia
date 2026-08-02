#!/usr/bin/env python3
"""Fail the build when the corpus contains a question that should never ship.

    python3 tools/corpus/quality_gate.py            # exits non-zero on a violation
    python3 tools/corpus/quality_gate.py --report   # list everything, exit 0

Every quality fix this session was REACTIVE: play, notice something bad, fix that
instance. That is unbounded work, because nothing stopped the next bad question
from appearing — the audit reported, and reporting is not a gate. This is the
gate. It runs over the shipped data files, not a sample of gameplay, so a defect
cannot slip through by not being drawn during a sweep.

Each rule below is here because a real question in this app hit it:

  READ-OFF        "Cædmon's Hymn -> Cædmon", "Singapore -> Singapore dollar" —
                  the answer is inside the question.
  ANSWER-IN-PROMPT "Headquartered in Dallas's Whitacre Tower ... AT&T".
  DUP-OPTION      the same option twice in one set of four.
  BROKEN-SHAPE    a mode's question with no shape payload, so Closest Call
                  silently renders as a plain MCQ.
  PLACEHOLDER     unresolved %@ / nil / Optional( in a prompt.
  ERA-SPREAD      four dated people spanning 400+ years, so the era in the clue
                  eliminates three options before any knowledge is applied.
  MACHINE-STEM    "In what year was Sir Gawain and the Green Knight founded or
                  created?" — a Wikidata property name left in the prose.
  THIN-COVERAGE   a mode x category the bundle cannot fill, which silently
                  serves a different category and says nothing.
  PRESENT-TENSE-PAST
                  a present-tense template asked of a subject the corpus itself
                  describes as historical: "What currency is used in the Songhai
                  Empire?" (fell 1591), "What is the capital of Alodia?". Five
                  templates written for present-day places, applied to every
                  polity the corpus knows. The test reads the DESCRIPTION, never
                  the name — plenty of live places are called a Kingdom, and
                  Indore State is historical where Washington State is not.
  PROMPT-REPETITION
                  one prompt text used so often that a round shows it twice.
                  Measured 2026-08-02: a ten-question draw repeated a prompt
                  VERBATIM 7.4% of the time, because four phrasings of "founded
                  earliest" covered 7,526 rows between them. Seeing the same
                  sentence twice in a round reads as a bug, not as two questions.
                  The rule caps any single prompt at 1% of the corpus.
  TERSE-STEM      a comparison asked as a headline fragment rather than a
                  sentence: "Most people of the four — which one?" (not
                  English), "Longest of the four — which one?" (longest WHAT?).
                  3,692 rows, while the SAME question type was already phrased
                  properly elsewhere in the corpus. The reveal states the
                  dimension out loud — "has the greatest population of the four
                  (23.9 million)" — so a prompt saying less than its own answer
                  panel is the defect.
  NUMBER-AGREEMENT
                  a singular verb with a plural subject: "In which country is the
                  Andaman Islands?". This one was INTRODUCED by the fix above —
                  adding the missing article made the disagreement audible where
                  "is Andaman Islands" had hidden it. A repair that only half
                  reads the sentence leaves it half wrong.
  MISSING-ARTICLE a template dropped a subject title into a slot where English
                  wants "the": "On which continent is Peace River?",
                  "Approximately what is the elevation of Appalachian
                  Mountains?". Found by reading rendered prompts. The list of
                  names is deliberately short — matching every "Sudan" and
                  "Valley" would produce "the Sudan" and "the Death Valley",
                  which is worse than the defect it fixes.
  CATEGORY-SKEW   a category grew past the share it had when Decision 050 was
                  written. "Mixed Bag" is only as mixed as the corpus, and the
                  corpus is 31% Film & TV against 2.4% Business — so a new
                  player, whose default is Mixed Bag, gets one film question in
                  three and one business question in forty. Found by generating
                  60 days of Daily sets and noticing 9 of them put 4+ of 7 in one
                  category; the picker turned out to be innocent (a uniform draw
                  over this corpus does that 18% of the time). This is a
                  REGRESSION GUARD, not a target: lowering a ceiling is the
                  improvement. See Decision 050 for why the draw was not changed.
  GOLDEN-STALE    the Create search golden names a question id the corpus no
                  longer contains. That golden is the six-platform contract
                  ("the same topic returns the same quiz everywhere") and the
                  Windows CreateGoldenTest links it directly, so dropping corpus
                  rows silently invalidates it. It went stale for three ticks
                  because the corpus resync regenerates the DAILY golden and not
                  this one, and only the Apple test suite was being run. Fix by
                  re-running tools/create/parity.sh --regenerate.
  NATIONALITY-FREE
                  the prompt names a nationality, the answer holds it, and EVERY
                  distractor is a different one — so the clue is decorative.
                  Found by rendering "Who is this American painter?" over Claude
                  Monet, Bob Ross, Caravaggio and Raphael. English/Scottish/Welsh
                  count as British (nobody eliminates Benedict Arnold from an
                  "English inventor" question because Wikidata says British), and
                  a hyphenated origin in the prompt is two claims, so both are
                  exempt.
  SLIDER-FARMABLE a Closest Call slider that pays a player who never moves it.
                  2,500 rows shared one 1000..2025 track, and since nearly every
                  subject is modern the answer sat at a median 0.93 of it —
                  "always guess 1985" scored 61.7% of the mode. Found by
                  rendering "In what year did Carole Lombard die?" and noticing
                  the player is asked to drag through a millennium. The rule
                  checks the two free strategies: one fixed guess for every
                  question, and leaving the slider where it opens.
  UNANSWERABLE-TYPEIN
                  a free-text question whose clue cannot produce one answer.
                  Found by rendering a Type Answer round: 'Who is this —
                  "Swedish actress (1915-1982)"?' over an empty text field. In
                  multiple choice a bare description is dull; with a text field
                  there is nothing to pick from. The worst were not close calls
                  ("What is this — 'Medical condition'?", "'U.S. state'?"), and
                  268 of the 474 named a description that does not identify a
                  unique subject even inside this corpus. The second half is the
                  fill-in-the-blank generator blanking EVERY occurrence of an
                  answer word: "Luna moth" turned "the American moon moth" into
                  "the American moon ____". One blank is a clue; two is damage.
  ODD-ONE-KIND    an Odd One Out set whose options are not all the same KIND.
                  In a mode that asks "which doesn't belong", a difference in
                  type IS an answer, so the set has two answers and the app marks
                  the obvious one wrong. Found by rendering a round: "Three of
                  these were created by Marta Kauffman" offered two shows and two
                  fictional characters; "created by Leonardo da Vinci" offered
                  three paintings and Sherlock Holmes; and one set answered
                  Livingston Island with the Mona Lisa sitting among three
                  countries. Wikidata's `creator` spans works and characters
                  alike, which is how a true relation produced a free question.
  DOUBLED-STEM    a stem verb repeated — "In which country is Nike, Inc. based
                  based based based?", which shipped on 1,022 questions. The
                  cause was a repair in this directory that was not idempotent:
                  fix_stem_type.py captures everything before the "?" as the
                  subject, so each run re-appended the verb it added last time.
                  The rule names only stem verbs, because "Duran Duran", "Bora
                  Bora" and "6 ft 3 in in her prime" are real prompts.
  NUMERIC-SORTED  numeric options presented in ascending order. This rule guards
                  a NON-obvious invariant: sorting them looks tidier and every
                  other quiz app does it, but distractors here are generated
                  AROUND the answer, so sorting lands the answer in a middle slot
                  80.8% of the time against 25% chance. Ordered years would hand
                  the player a heuristic worth three times chance. Measured
                  2026-08-01 after a rendered Sweep round showed 2011/2016/2019/
                  2015 and the shuffle looked like a bug. It is not a bug.
  STUB-REVEAL     a reveal whose description is a bare number — "Matthew Perry:
                  1969." Found by rendering a Sweep round and reading the payoff
                  panel. 29,020 rows did this, and for 2,425 the number WAS the
                  whole reveal. Every classifier in tools/corpus skipped them on
                  `d[0].isdigit()`, so the field the player reads was the one
                  field no machine checked.
  CITY-LANGUAGE   "Which of these is an official language of Thessaloniki?" —
                  a country-level fact asked of a city, so the city's name gives
                  it away. Kept only where the city genuinely differs from its
                  country (Dakar -> Wolof in French-speaking Senegal).
  KIND-MISMATCH   an option that is a different KIND of thing from the answer —
                  "European hornet" among Myrtle, Nerium and Date palm, for a
                  clue about a shrub. Nobody needs the fact to solve that.
  STEM-TYPE       "In which country is Russo-Ukrainian war?" — one Wikidata
                  property mapped to one stem and applied to every kind of
                  subject. The second question of this session's first playtest
                  was "In which country is Germanwings Flight 9525?".

Thresholds are the count that ships TODAY, so the gate locks in progress and
fails on regression. Lower them as content improves; never raise one to make a
build pass.
"""
import argparse
import collections
import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
A = ROOT / "assets"

# rule -> how many known instances are tolerated. Every one of these should be
# trending to zero; a PR that raises a number is doing the wrong thing.
BUDGET = {
    "READ-OFF": 0,
    "ANSWER-IN-PROMPT": 0,      # the 6 that existed were dropped, not budgeted
    "DUP-OPTION": 0,
    "BROKEN-SHAPE": 0,
    "PLACEHOLDER": 0,
    "ERA-SPREAD": 0,            # 401 repaired by occupation+era; 44 unrepairable, dropped
    "MACHINE-STEM": 0,
    "THIN-COVERAGE": 0,
    "STEM-TYPE": 0,
    # 3 = the three the CLASSIFIER cannot type, not three bad questions. The
    # film "Insomnia (2002 film)" renders as bare "Insomnia" and collides with
    # the sleep disorder; "Harpy" is a mythological creature; "Jesus Christ
    # Superstar" collides with a person. Their options are internally consistent
    # — films with films, people with people. Raising a budget to hide a defect
    # is forbidden; recording what a rule provably cannot see is not the same
    # thing, and pretending otherwise would mean deleting good questions.
    # Dakar -> Wolof, Asmara -> Arabic, Nuuk -> Greenlandic: three cities whose
    # official language really is not their country's, which is the interesting
    # question this rule exists to protect. Auckland -> English looked like a
    # fourth and was not; it is dropped by id in fix_city_language.py.
    # Ascending happens by chance in 1/24 of four-option sets, and 4.2% is what
    # the corpus shows. Anything materially above that means someone sorted.
    "NUMERIC-SORTED": 0,
    "PRESENT-TENSE-PAST": 0,
    "PROMPT-REPETITION": 0,
    "TERSE-STEM": 0,
    "NUMBER-AGREEMENT": 0,
    "MISSING-ARTICLE": 0,
    "CATEGORY-SKEW": 0,
    "GOLDEN-STALE": 0,
    "NATIONALITY-FREE": 0,
    "SLIDER-FARMABLE": 0,
    "UNANSWERABLE-TYPEIN": 0,
    "ODD-ONE-KIND": 0,
    "DOUBLED-STEM": 0,
    "STUB-REVEAL": 0,
    "CITY-LANGUAGE": 3,
    "KIND-MISMATCH": 3,
}

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for",
        "de", "la", "le", "el", "s", "is", "was", "or"}

# Wikidata property names and template scaffolding that must never reach a
# player. "founded or created" shipped on 451 rows, including Auschwitz.
# Narrowed after its first run reported 16 violations of which 16 were mine:
# `\binception\b` matched twelve references to the FILM Inception, and
# "instance of" matched a sentence of ordinary English. A gate that cries wolf
# gets its budget raised, which is the failure mode this file exists to prevent.
# Only phrases that are never natural prose survive.
MACHINE = re.compile(
    r"founded or created|\bwikidata\b|\bqid\b|\bQ\d{4,}\b|"
    r"significant event|subclass of|\bP\d{2,4}:", re.I)
# A city or sub-national unit that is not itself a state.
CITY_DESC = re.compile(r"\b(city|town|village|county|municipality|district|borough|"
                       r"commune|prefecture|parish|neighborhood)\b(?!.*\b(country|"
                       r"sovereign|kingdom|republic|empire|nation)\b)", re.I)
PLACEHOLDER = re.compile(r"%@|%\d*\$?[sd]|\{\}|\bnil\b|Optional\(|\bNaN\b|\bundefined\b")

# "In which country is X?" only parses when X is a PLACE. Asked of an event, an
# organization or a song it is not a hard question, it is a broken sentence.
# The repaired forms end in "based?" / "take place?" and must not match — `.+`
# happily swallowed "Juventus FC based", so the first run of this rule failed on
# the 407 questions it had just fixed.
LOCATIVE_STEM = re.compile(r"^In which country is (?!.*\b(?:based|take place|located)\?$).+\?$")
NOT_A_PLACE = re.compile(
    r"\b(crash|disaster|flight|accident|battle|war\b|massacre|attack|siege|earthquake|"
    r"eruption|hurricane|shooting|bombing|riot|protest|revolution|election|treaty|"
    r"uprising|offensive|campaign|landing|genocide|famine|pandemic|coup|rebellion|"
    r"company|corporation|conglomerate|manufacturer|retailer|airline|brand|club|team|"
    r"university|bank|studio|publisher|broadcaster|agency|band\b|"
    r"film|movie|song|album|single|novel|book|poem|series|sitcom|anime|video game|"
    r"manga|painting|opera|symphony|musical|anthem)\b", re.I)

SHAPE_FILES = {
    "picture.json":    ("pictureId", 10, 4, 9),    # (mode, per-round, cat idx, shape idx)
    "thisorthat.json": ("thisOrThat", 10, 4, None),
    "closest.json":    ("closestCall", 8, 8, None),
    "order.json":      ("ordering", 6, 4, None),
    "match.json":      ("matching", 6, 4, None),
    "typeanswer.json": ("typeAnswer", 8, 4, None),
    "oddoneout.json":  ("oddOneOut", 8, 4, None),
    "enumerate.json":  ("enumerate", 3, 3, None),
}
CATEGORIES = ["history", "science", "geography", "arts", "screen", "music",
              "sports", "business"]


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


def reads_off(a, b):
    """Can one side be read off the other, with no knowledge?"""
    aw, bw = sig(a), sig(b)
    if not aw or not bw:
        return False
    if aw & bw or aw.issubset(bw) or bw.issubset(aw):
        return True
    # The adjectival form: Russia/Russian, India/Indian.
    return any(len(x) >= 4 and len(y) >= 4 and (x.startswith(y) or y.startswith(x))
               for x in aw for y in bw)


def load(name):
    p = A / name
    return json.loads(p.read_text())["questions"] if p.exists() else []


def birth_years():
    out = {}
    ents = json.loads((A / "enrich.json").read_text())["entities"]
    for t, e in ents.items():
        b = e.get("numbers", {}).get("birth_year")
        if b:
            out[t.replace("_", " ")] = int(b["value"])
    return out


# Same vocabulary the repair uses (tools/corpus/fix_kind_distractors.py); the
# two must not drift, or the gate flags rows the repair cannot see.
# "1969." / "c. 1450" / "-44 BCE" standing where a description should be.
HISTORICAL_DESC = re.compile(
    r"\b(former|historical|defunct|extinct|dissolved|abolished)\b"
    r"|\(\s*c?\.?\s*\d{3,4}\s*[-\u2013]\s*\d{3,4}\s*\)"
    r"|\bwas a\b|\bwere a\b", re.I)
PRESENT_TEMPLATES = ("What currency is used in ", "In which country is ",
                     "What is the capital of ", "What is the official language of ",
                     "Which of these is an official language of ",
                     "On which continent is ")

TERSE_STEM = re.compile(r"of the four \u2014 which one\?$")
SYMBOL_BACKWARDS = re.compile(r"^On the periodic table, .+ is which symbol\?$")

PLURAL_SUBJECT = re.compile(
    r"\b(Islands|Mountains|Alps|Andes|Himalayas|Rockies|Pyrenees|Balkans|"
    r"Highlands|Everglades|Badlands|Netherlands|Philippines|Bahamas|Maldives|"
    r"Seychelles|Comoros|Falklands)$")

TAKES_THE = re.compile(
    r"(?:^|\s)(?:Mountains|Islands|Alps|Andes|Himalayas|Rockies|Pyrenees|"
    r"Balkans|Highlands|Everglades|Badlands|Netherlands|Philippines|Bahamas|"
    r"Maldives|Seychelles|United States|United Kingdom|Soviet Union)$"
    r"|\b(?:Sea|Ocean|Gulf|Strait|Channel|River|Desert|Range|Peninsula|"
    r"Archipelago|Delta|Basin|Empire|Republic|Federation|Union)$")
ARTICLE_PREP = r"\b(?:of|in|is|to|for|from|across|near|along|around|through)\s+"

DOUBLED_VERB = re.compile(
    r"\b(based|located|situated|headquartered|founded|set|born|made)\s+\1\b", re.I)

NUMERIC_OPT = re.compile(r"^-?\d[\d,]*(?:\.\d+)?$")

STUB_DESC = re.compile(
    r"^\s*(?:c\.\s*)?-?\d{1,4}(?:\s*(?:BCE?|AD|CE))?\s*[.,;]?\s*$", re.I)

# A fictional character is a kind of its own, and the corpus says so in prose
# even when the description slot holds something else (Ross Geller's holds the
# actor's name). This one signal reads the whole explanation.
BARE_DESC = re.compile(r'^(?:Who|What) is this\s*[\u2014-]\s*'
                       r'["\u201c\u201d][^"\u201c\u201d]{4,120}["\u201c\u201d]\s*\?$')


def typein_verdict(prompt):
    """Why a free-text clue cannot be answered, or None. Mirrors
    fix_typeanswer_clues.py — see that file for what each shape looked like."""
    p = str(prompt or "")
    if BARE_DESC.match(p):
        return "bare description as the whole clue"
    blanks = len(re.findall(r"_{2,}", p))
    if p.startswith("Fill in the blank:") and blanks > 1:
        return f"{blanks} blanks"
    return None


_NATIONS = ("American|British|English|French|Italian|German|Spanish|Dutch|Russian|"
            "Japanese|Chinese|Indian|Canadian|Australian|Swedish|Norwegian|Danish|"
            "Polish|Greek|Irish|Scottish|Mexican|Brazilian|Argentine|Austrian|Swiss|"
            "Belgian|Portuguese|Turkish|Korean|Egyptian|Nigerian|Israeli|Iranian|"
            "Hungarian|Czech|Finnish|Romanian|Ukrainian|Welsh|Colombian|Chilean|"
            "Cuban|Peruvian|Vietnamese|Thai|Indonesian|Filipino|Pakistani")
NAT_IN_PROMPT = re.compile(r"\bthis\s+(" + _NATIONS + r")\b", re.I)
NAT_IN_DESC = re.compile(r"^(" + _NATIONS + r")\b", re.I)
NAT_HYPHEN = re.compile(r"\bthis\s+\w+-\w+", re.I)
_NAT_FAMILY = {"english": "british", "scottish": "british", "welsh": "british"}


def _nat_family(n):
    return _NAT_FAMILY.get(n.lower(), n.lower())


CHARACTER = re.compile(r"\bis a fictional\b|\bfictional character\b"
                       r"|\bmain characters? of\b|\bis a character\b"
                       r"|\btitular character\b", re.I)


def option_kind(name, kinds, raw_expl):
    name = str(name)
    if CHARACTER.search(raw_expl.get(name, "")):
        return "character"
    return kinds.get(name)


SOVEREIGN_NAME = re.compile(
    r"\b(empire|republic|kingdom|caliphate|sultanate|duchy|confederation|"
    r"kaganate|khanate|dynasty|state)\b", re.I)

_KINDS = [
    ("plant",    r"\b(plant|shrub|tree|flower|grass|fern|moss|herb|vine|flowering plant|conifer|palm|cactus)\b"),
    ("animal",   r"\b(insect|bird|mammal|fish|reptile|amphibian|spider|beetle|wasp|hornet|moth|butterfly|dinosaur|crustacean|mollusc|primate)\b"),
    ("person",   r"\b(born \d{4}|politician|footballer|actor|actress|singer|writer|player|physicist|philosopher|emperor|monarch|composer|director|mathematician|musician|scientist|chemist|biologist|astronomer|economist|historian|archaeologist|psychologist|linguist|botanist|zoologist|geologist|primatologist|engineer|architect|painter|sculptor|poet|novelist|playwright|screenwriter|journalist|editor|dancer|choreographer|conductor|guitarist|pianist|violinist|drummer|rapper|filmmaker|producer|presenter|broadcaster|comedian|activist|entrepreneur|magnate|philanthropist|explorer|astronaut|physician|surgeon|nurse|lawyer|judge|professor|teacher|leader|statesman|king|queen|sultan|caliph|tsar|premier|president|chancellor|dictator|revolutionary|general|admiral|soldier|athlete|swimmer|boxer|cyclist|wrestler|jockey|manager|coach|quarterback|midfielder|goalkeeper|striker|winger|batsman|bowler|author|artist|commentator|illustrator|cartoonist|animator|designer|inventor|banker|songwriter|novelist|essayist|critic|theologian|missionary|aviator|racer|pilot|spy|outlaw|chief|saint|prophet|rabbi|imam|bishop|pope|cardinal|abbot|monk|nun)\b"),
    ("place",    r"\b(country|city|town|village|island|river|mountain|region|province|capital|lake|desert|county|municipality)\b"),
    ("work",     r"\b(film|movie|song|album|novel|book|poem|series|sitcom|anime|video game|painting|opera|symphony|manga|sculpture)\b"),
    ("org",      r"\b(company|corporation|club|team|university|bank|airline|band|agency|organisation|organization|brand)\b"),
    ("event",    r"\b(battle|war\b|siege|revolution|treaty|massacre|disaster|earthquake|eruption|pandemic|election)\b"),
    ("chemical", r"\b(chemical element|compound|molecule|protein|enzyme|mineral|isotope)\b"),
    ("disease",  r"\b(disease|disorder|syndrome|infection|cancer|virus|bacterium)\b"),
]
_KINDS = [(n, re.compile(p, re.I)) for n, p in _KINDS]


# A description is only readable as a TYPE when two things hold, and both were
# discovered by rendering reveals and reading them (2026-08-01):
#
#   1. The explanation actually has the "Subject: description" shape. For 2,650
#      rows the first colon is INSIDE the text — "Parthia (Old Persian: Parθava;
#      ...) is a historical region" — so splitting on it fed every classifier
#      here the fragment "Parθava; Middle Persian" as Parthia's description.
#      Those reveals are fine for the player; the app renders the explanation
#      verbatim. It is the classifiers that were reading garbage.
#
#   2. The description is a terse Wikidata one-liner ("American actress
#      (born 1989)"), not a Wikipedia lead sentence. A lead sentence names many
#      nouns in passing — "a German Waffen-SS tank commander during the Second
#      World War" typed Michael Wittmann as an EVENT. Skipping prose costs
#      coverage; misreading it costs correct distractors, which is worse.
# A Wikidata description is a NOUN PHRASE: "American mathematician (1918-2020)",
# "Country in Oceania", "Sculpture by Anish Kapoor in Chicago". It contains no
# finite verb. A Wikipedia lead sentence always does. Testing for "is/was a" was
# too weak — "It was ADAPTED into a 1988 film" typed Dian Fossey as a work,
# "Born in New York City" typed William F. Buckley Jr. as a place. Rejecting a
# prose sentence costs coverage; misreading one costs correct distractors.
PROSE = re.compile(r"\b(?:is|was|are|were|has|had|have|been|became|begin|began|"
                   r"begun|won|win|released|adapted|founded|formed|died|starred|"
                   r"appeared|wrote|written|played|serves|served|includes|"
                   r"consists|contains|features|remains|made|took|held|ran|"
                   r"grew|rose|led|joined|left|moved|settled|returned)\b"
                   r"|\(born\s|^Born\b|^It\b|^Its\b|^They\b|^He\b|^She\b", re.I)


def readable_description(expl, subject):
    """The subject's TYPE, or None when the field cannot be trusted to carry it."""
    if not expl or ":" not in expl or "\u2192" in expl:
        return None
    head, rest = expl.split(":", 1)
    if head.strip() != (subject or "").strip():
        return None
    d = re.split(r"(?<=[.!?])\s", rest.strip(), maxsplit=1)[0].strip()
    if not d or len(d) <= 8 or len(d) > 120 or d[0].isdigit() or PROSE.search(d):
        return None
    # The TYPE lives in the head noun phrase. A Wikidata description opens with
    # what the thing IS and then qualifies it, so anything after the first
    # bracket, comma or relative pronoun is about the subject's LIFE, not its
    # kind. Matching the whole string typed Katherine Johnson ("American
    # mathematician (1918-2020)", elsewhere "...at the space AGENCY") as an org,
    # and Dian Fossey as a WORK because another row named her book. Truncating
    # here can only ever match less, never more.
    # "(born 1938)" is a person and nothing else. A bare year RANGE is not: the
    # first version of this rule accepted "(1918-2020)" and promptly typed
    # Nine Years' War (1688-1697), Cao Wei (220-266) and the soap opera
    # Neighbours (1985-2022) as people, which is how KIND-MISMATCH went from
    # 598 to 1,509. Dates bound things that end, not only people.
    if re.search(r"\(born\s+\d{3,4}\)", d):
        return "PERSON-BY-DATES"
    return re.split(r"\s*[(\[,;]|\s+(?:who|which|that|known|best|famous|based)\s",
                    d, maxsplit=1)[0].strip()


def copula_type(expl, subject):
    """The predicate of "<Subject> is/was a/an <predicate>", or None.

    readable_description deliberately refuses prose, because a lead sentence
    names many nouns in passing. But one prose shape IS a type statement: the
    sentence whose grammatical subject is the subject itself. "Royal Enfield is
    an Indian motorcycle manufacturer" says what Royal Enfield is; "The battle
    helped the British East India Company" does not say what the Battle of
    Plassey is, and refiled it as BUSINESS when a tool read it as one.

    Only the copula form counts, and only when the sentence opens with the
    subject's own name.
    """
    if not expl or ":" not in expl or "\u2192" in expl or not subject:
        return None
    head, rest = expl.split(":", 1)
    if head.strip() != subject.strip():
        return None
    d = re.split(r"(?<=[.!?])\s", rest.strip(), maxsplit=1)[0].strip()
    lead = re.escape(subject.split(" (")[0])
    m = re.match(rf"{lead}\b[^.]{{0,60}}?\b(?:is|was|are|were)\s+(?:a|an|the)\s+(.{{6,90}})",
                 d, re.I)
    return m.group(1).strip() if m else None


def kind_map(rows):
    """name -> kind, only where the name means exactly one thing."""
    # One subject, one description. kind_map used to union the kinds of EVERY
    # row that named a subject, so a single row whose description wandered
    # decided the type: Bob Kane came out a WORK, William F. Buckley Jr. a
    # PLACE, Penicillin a PERSON. Take the description the corpus states most
    # often for that subject and classify only that.
    canon = collections.defaultdict(collections.Counter)
    for q in rows:
        d = readable_description(q[6] or "", q[7])
        if d:
            canon[q[7]][d] += 1

    seen = collections.defaultdict(set)
    for subject, counts in canon.items():
        d = counts.most_common(1)[0][0]
        if d == "PERSON-BY-DATES":
            seen[subject].add("person")
            continue
        # A quoted word is being MENTIONED, not used as a type. "Vespa: Italian
        # scooter... Italian for 'wasp'" typed a scooter brand as an animal.
        d = re.sub(r"[\"'\u2018\u2019\u201c\u201d][^\"'\u2018\u2019\u201c\u201d]{1,30}"
                   r"[\"'\u2018\u2019\u201c\u201d]", " ", d)
        for n, rx in _KINDS:
            if rx.search(d):
                seen[subject].add(n)
                break

    # A bare name is ambiguous when the corpus ALSO holds a parenthetical twin:
    # "Vespa" the wasp beside "Vespa (brand)"; "Puma" the cat beside "Puma
    # (brand)"; "Insomnia" the disorder beside "Insomnia (2002 film)". The option
    # renders as the bare name, so the kind lookup silently picks the wrong
    # subject and calls a scooter maker an animal. Drop those names rather than
    # guess which one is meant.
    titles = {q[7] for q in rows if q[7]}
    ambiguous = {t for t in titles if any(
        o != t and o.startswith(t + " (") for o in titles)}
    # A bare name is ambiguous when MORE THAN ONE subject claims it, not merely
    # because some subject carries a parenthetical. The blanket version dropped
    # "Amazon" as ambiguous even though "Amazon (company)" is its only claimant,
    # which mattered the moment noise-only parentheticals were stripped from the
    # options: every simplified cell would have stopped resolving to a type and
    # the gate would have quietly lost coverage rather than reported it.
    claimants = collections.defaultdict(set)
    for t in titles:
        claimants[t.split(" (")[0]].add(t)
    ambiguous |= {b for b, owners in claimants.items() if len(owners) > 1}
    # A bare name whose sole claimant is a parenthetical title inherits its kind.
    for b, owners in claimants.items():
        if len(owners) == 1 and b not in seen:
            only = next(iter(owners))
            if only != b and only in seen:
                seen[b] = seen[only]
    return {k: next(iter(v)) for k, v in seen.items()
            if len(v) == 1 and k not in ambiguous}


def check():
    """rule -> list of human-readable violations."""
    bad = collections.defaultdict(list)
    years = birth_years()

    # ---- the corpus itself -------------------------------------------------
    rows_all = load("corpus.json")
    kinds = kind_map(rows_all)
    # Wikidata Q3024240 = "historical country" — on the Kingdom of Navarre, not
    # on France. Stated as data rather than sniffed from prose.
    HISTORICAL_TITLES = set()
    _src = ROOT / "tools" / "corpus" / "corpus_source.sqlite"
    if _src.exists():
        import sqlite3 as _sq
        _db = _sq.connect(f"file:{_src}?mode=ro", uri=True)
        HISTORICAL_TITLES = {t for t, p31 in _db.execute("select title, p31 from subject")
                             if p31 and "Q3024240" in p31}
        _db.close()

    nationality = {}
    for _q in rows_all:
        _d = readable_description(_q[6] or "", _q[7])
        if _d and _d != "PERSON-BY-DATES":
            _m = NAT_IN_DESC.match(_d)
            if _m:
                nationality.setdefault(_q[7], _nat_family(_m.group(1)))
    raw_expl = {}
    for _q in rows_all:
        if _q[7] and _q[6]:
            raw_expl.setdefault(_q[7], _q[6])
    # Subject descriptions, for the stem-type check.
    subject_desc = {}
    for q in rows_all:
        e = q[6] or ""
        if ":" in e and "\u2192" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            # First sentence only — same reason as kind_map. Reading the whole
            # enriched reveal matched "flight-test programme" and flagged a
            # fighter jet's question, while the REPAIR (which reads the same
            # field) could see nothing typeable in it. The gate and the repair
            # must read the same text or they argue forever.
            d = re.split(r"(?<=[.!?])\s", d, maxsplit=1)[0].strip()
            if d and not d[0].isdigit() and len(d) > 8:
                subject_desc.setdefault(q[7], d)

    # This one is a RATE, not a row count: ascending is chance 1-in-24, so a
    # handful of ascending sets is normal and only the proportion is evidence.
    numeric_total, numeric_sorted = [0], [0]
    for q in rows_all:
        prompt, opts, ci = q[1], q[2], q[3]
        if LOCATIVE_STEM.match(prompt or "") and NOT_A_PLACE.search(subject_desc.get(q[7], "")):
            bad["STEM-TYPE"].append(f"{q[0]}: {prompt[:70]}")
        # A sovereign entity named as one is not a city, whatever its lead
        # paragraph mentions. Same test as fix_city_language.py — the gate and
        # the repair have to agree or the budget drifts to cover the difference.
        if ("official language of" in (prompt or "")
                and CITY_DESC.search(subject_desc.get(q[7], ""))
                and not SOVEREIGN_NAME.search(q[7] or "")):
            bad["CITY-LANGUAGE"].append(f"{q[0]}: {prompt[:70]}")
        if opts and len(opts) >= 4 and all(NUMERIC_OPT.match(str(o).strip()) for o in opts):
            vals = [float(str(o).replace(",", "")) for o in opts]
            numeric_total[0] += 1
            if vals == sorted(vals):
                numeric_sorted[0] += 1
        if opts and len(opts) >= 4 and 0 <= ci < len(opts):
            _m = NAT_IN_PROMPT.search(prompt or "")
            if _m and not NAT_HYPHEN.search(prompt or ""):
                _want = _nat_family(_m.group(1))
                if nationality.get(str(opts[ci])) == _want:
                    _others = [str(o) for i, o in enumerate(opts) if i != ci]
                    _known = [nationality[o] for o in _others if o in nationality]
                    if len(_known) == len(_others) and all(k != _want for k in _known):
                        bad["NATIONALITY-FREE"].append(
                            f"{q[0]}: {_want} answer, distractors {sorted(set(_known))}")
        _subj = q[7] or ""
        if _subj and prompt and (_subj in HISTORICAL_TITLES
                                 or HISTORICAL_DESC.search(raw_expl.get(_subj, ""))):
            for _pres in PRESENT_TEMPLATES:
                if prompt.startswith(_pres):
                    bad["PRESENT-TENSE-PAST"].append(f"{q[0]}: {prompt[:66]}")
                    break
        if _subj and prompt and PLURAL_SUBJECT.search(_subj):
            for _sing in ("In which country is ", "In which country was ",
                          "On which continent is ", "On which continent was "):
                if prompt.startswith(_sing):
                    bad["NUMBER-AGREEMENT"].append(f"{q[0]}: {prompt[:64]}")
                    break
        if _subj and TAKES_THE.search(_subj) and prompt:
            if (re.search(ARTICLE_PREP + re.escape(_subj) + r"\b", prompt)
                    and not re.search(r"\bthe\s+" + re.escape(_subj) + r"\b",
                                      prompt, re.I)):
                bad["MISSING-ARTICLE"].append(f"{q[0]}: {prompt[:66]}")
        if TERSE_STEM.search(prompt or "") or SYMBOL_BACKWARDS.match(prompt or ""):
            bad["TERSE-STEM"].append(f"{q[0]}: {(prompt or '')[:60]}")
        if DOUBLED_VERB.search(prompt or ""):
            bad["DOUBLED-STEM"].append(f"{q[0]}: {(prompt or '')[:70]}")
        if STUB_DESC.match((q[6] or "").split(":", 1)[-1].strip()):
            bad["STUB-REVEAL"].append(f"{q[0]}: {(q[6] or '')[:60]}")
        if PLACEHOLDER.search(prompt or ""):
            bad["PLACEHOLDER"].append(f"{q[0]}: {prompt[:70]}")
        if MACHINE.search(prompt or ""):
            bad["MACHINE-STEM"].append(f"{q[0]}: {prompt[:70]}")
        if not opts or not (0 <= ci < len(opts)):
            continue
        folded = [fold(o) for o in opts]
        if len(set(folded)) < len(folded):
            bad["DUP-OPTION"].append(f"{q[0]}: {opts}")
        # The answer spelled out in its own prompt. Interrogatives are excluded:
        # "The Who" matched "Who composed the score for CSI?" because the answer's
        # only significant word is the question word.
        aw = sig(opts[ci]) - {"who", "what", "when", "where", "which", "why", "how"}
        if aw and aw.issubset(sig(prompt)) and len(fold(opts[ci])) > 3:
            bad["ANSWER-IN-PROMPT"].append(f"{q[0]}: '{opts[ci]}' in {prompt[:60]}")
        ys = [years.get(str(o)) for o in opts]
        if len(opts) >= 4 and all(ys) and max(ys) - min(ys) > 400:
            bad["ERA-SPREAD"].append(f"{q[0]}: {max(ys) - min(ys)}y {opts}")
        if len(opts) >= 4:
            ka = kinds.get(str(opts[ci]))
            odd = [str(o) for i, o in enumerate(opts)
                   if i != ci and kinds.get(str(o)) and ka and kinds[str(o)] != ka]
            if ka and odd:
                bad["KIND-MISMATCH"].append(f"{q[0]}: {odd} among {ka}s — {opts}")

    # Ceilings re-measured 2026-08-02 after the date-padding prune (Decision 050,
    # "Amended"). SCREEN came DOWN 32.5% -> 30.5%, which is the improvement;
    # GEOGRAPHY went UP 19.5% -> 21.5% without gaining a single row, because it
    # held fewer date questions than everyone else and 18,004 of theirs went. A
    # ceiling that rises for that reason is honest; one that rises because a
    # category grew is the thing this rule exists to stop.
    SHARE_CEILING = {"screen": 0.305, "geography": 0.215, "music": 0.125,
                     "history": 0.100, "sports": 0.095, "arts": 0.095,
                     "science": 0.080}
    cat_counts = collections.Counter(q[4] for q in rows_all)
    cat_total = sum(cat_counts.values())
    if cat_total:
        for cat, ceiling in SHARE_CEILING.items():
            share = cat_counts.get(cat, 0) / cat_total
            if share > ceiling:
                bad["CATEGORY-SKEW"].append(
                    f"{cat} is {share:.1%} of the corpus, ceiling {ceiling:.1%}"
                    " — grow another category rather than raising this")

    prompt_counts = collections.Counter(q[1] or "" for q in rows_all)
    if rows_all:
        for _p, _n in prompt_counts.most_common(6):
            if _n / len(rows_all) > 0.01:
                bad["PROMPT-REPETITION"].append(
                    f"{_n} rows ({_n/len(rows_all):.1%}) share one prompt: {_p[:48]}")

    golden = ROOT / "tools" / "create" / "golden" / "search.txt"
    if golden.exists():
        known = {q[0] for q in rows_all}
        missing = set()
        for line in golden.read_text().splitlines():
            if "\t" not in line:
                continue
            for qid in line.split("\t", 1)[1].split():
                if qid and qid not in known:
                    missing.add(qid)
        if missing:
            bad["GOLDEN-STALE"].append(
                f"{len(missing)} id(s) gone from the corpus, e.g. {sorted(missing)[:3]}"
                " — run tools/create/parity.sh --regenerate")

    closest = load("closest.json") or []
    if closest:
        def _scores(guess, rs):
            return sum(1 for r in rs if abs(guess - r[2]) <= r[6])
        yr = [r for r in closest if len(r) > 6 and 1000 <= r[2] <= 2025
              and isinstance(r[6], (int, float))]
        if yr:
            best = max(range(1000, 2026), key=lambda g: _scores(g, yr))
            rate = _scores(best, yr) / len(yr)
            if rate > 0.20:
                bad["SLIDER-FARMABLE"].append(
                    f"one fixed guess ({best}) scores {rate:.1%} of year sliders")
            mid = sum(1 for r in yr if abs((r[3] + r[4]) / 2 - r[2]) <= r[6]) / len(yr)
            if mid > 0.20:
                bad["SLIDER-FARMABLE"].append(
                    f"never moving the slider scores {mid:.1%} of year sliders")

    if numeric_total[0]:
        rate = numeric_sorted[0] / numeric_total[0]
        if rate > 0.08:                      # chance is 1/24 = 4.2%
            bad["NUMERIC-SORTED"].append(
                f"{rate:.1%} of {numeric_total[0]} numeric option sets are ascending "
                f"(chance is 4.2%) — someone sorted them; see the rule note")

    # ---- the shape sources -------------------------------------------------
    for name, (mode, per_round, cat_i, shape_i) in SHAPE_FILES.items():
        rows = load(name)
        if not rows:
            bad["BROKEN-SHAPE"].append(f"{name} is missing or empty")
            continue
        counts = collections.Counter()
        for r in rows:
            if len(r) > cat_i and isinstance(r[cat_i], str):
                counts[r[cat_i]] += 1
            if PLACEHOLDER.search(str(r[1])):
                bad["PLACEHOLDER"].append(f"{r[0]}: {str(r[1])[:70]}")
            if MACHINE.search(str(r[1])):
                bad["MACHINE-STEM"].append(f"{r[0]}: {str(r[1])[:70]}")
            if shape_i is not None and (len(r) <= shape_i or not r[shape_i]):
                bad["BROKEN-SHAPE"].append(f"{r[0]}: {mode} row has no shape payload")
            # Odd One Out only works when the ONLY way to spot the outlier is the
            # fact. Options of mixed type hand the player a second answer.
            # STUB-REVEAL, in the files corpus.json does not own. Checking only
            # corpus rows let "Whitney Houston: 2012." keep rendering in Closest
            # Call, which carries its own explanation cell.
            for cell in r:
                if isinstance(cell, str) and ":" in cell and "\u2192" not in cell:
                    d = cell.split(":", 1)[1].strip()
                    if STUB_DESC.match(re.split(r"(?<=[.!?])\s", d, maxsplit=1)[0].strip()):
                        bad["STUB-REVEAL"].append(f"{r[0]}: {cell[:56]}")
                        break
            if name == "typeanswer.json":
                v = typein_verdict(r[1])
                if v:
                    bad["UNANSWERABLE-TYPEIN"].append(f"{r[0]}: {v} — {str(r[1])[:52]}")
            if name == "oddoneout.json" and len(r) > 2 and r[2]:
                ks = {option_kind(o, kinds, raw_expl) for o in r[2]}
                ks.discard(None)
                if len(ks) > 1:
                    bad["ODD-ONE-KIND"].append(
                        f"{r[0]}: {sorted(ks)} — {[str(o) for o in r[2]]}")
        # Match Up: neither side may give the other away.
        if name == "match.json":
            for r in rows:
                for k, v in zip(r[2], r[3]):
                    if reads_off(k, v):
                        bad["READ-OFF"].append(f"{r[0]}: {k} -> {v}")
        # Every category must hold at least one round's worth.
        for c in CATEGORIES:
            if counts.get(c, 0) < per_round:
                bad["THIN-COVERAGE"].append(
                    f"{mode} x {c}: {counts.get(c, 0)} rows, a round needs {per_round}")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="list and exit 0")
    ap.add_argument("--full", action="store_true")
    a = ap.parse_args()

    bad = check()
    failed = False
    print(f"{'rule':18}{'found':>7}{'budget':>8}   status")
    for rule in sorted(BUDGET):
        n, cap = len(bad.get(rule, [])), BUDGET[rule]
        ok = n <= cap
        failed |= not ok
        print(f"{rule:18}{n:>7}{cap:>8}   {'ok' if ok else 'FAIL'}")
        if not ok or a.full:
            for v in bad.get(rule, [])[: (None if a.full else 5)]:
                print(f"      {v}")
    unknown = set(bad) - set(BUDGET)
    for rule in sorted(unknown):
        failed = True
        print(f"{rule:18}{len(bad[rule]):>7}{'—':>8}   FAIL (no budget defined)")

    if a.report:
        return 0
    if failed:
        print("\nA question that should never ship is in the data. Fix the content, "
              "or the generator that produced it — do not raise a budget.")
        return 1
    print("\nquality gate passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
