#!/usr/bin/env python3
"""Score every question on whether it is any GOOD, and rank the worst.

    python3 tools/play/content_audit.py            # the summary + worst offenders
    python3 tools/play/content_audit.py --rule ELIMINABLE --show 30
    python3 tools/play/content_audit.py --ids ELIMINABLE 12   # ids, for rendering

`quality_gate.py` answers "should this ship" with yes or no. That is the wrong
shape for craft: almost every question passes it and plenty are still dull,
guessable or unfair. This scores instead, so the corpus can be walked worst-first
by a person rather than sampled at random — which is how a real editor works
through a slush pile.

The scores are proxies for the judgements a player makes in about a second:

  ELIMINABLE   how many of the three distractors can be ruled out WITHOUT
               knowing the fact — by type (a year among names), era (a pharaoh
               beside a modern politician), domain (three politicians beside a
               ski jumper) or length. 3 means the question answers itself.
  TEMPLATED    the prompt is a bare relation stem ("What is the capital of X?")
               rather than a written clue. Not wrong; just not a good question,
               and the corpus has a delight pass precisely because that matters.
  HOLLOW       the explanation only restates the answer ("Netflix: United
               States"), so the reveal teaches nothing. The whole product thesis
               is that the reveal is a curiosity door.
  AWKWARD      the prompt reads as machine output — doubled articles, a missing
               one, a dangling preposition, a stem that does not parse.
  LAYOUT       the question is most likely to break the SCREEN: a very long
               option, an unbreakable token wider than the button, a
               right-to-left or CJK script, or four long options at once.
               Ranked so the rendered check can look at the worst instead of
               watching random games and hoping.

Nothing here fails a build. It produces a reading list.
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

STOP = {"the", "of", "a", "an", "and", "in", "on", "at", "to", "for", "de",
        "la", "le", "el", "s", "is", "was", "or", "which", "what", "who"}

NUM = re.compile(r"^-?[\d,]+(\.\d+)?$")
YEAR = re.compile(r"^-?\d{3,4}(\s*(bc|bce|ad|ce))?$")

# A prompt built straight from a relation, with no clue written around it.
TEMPLATED = re.compile(
    r"^(what is the (capital|currency|atomic number) of|"
    r"in which country (is|did)|which country is|who (wrote|composed|directed|founded|created) |"
    r"who is the performer of|which company manufactures|"
    r"which of these is an official language of|"
    r"who is credited with discovering|what currency is used in)", re.I)

# Prose that reads as generated rather than written.
AWKWARD = re.compile(
    r"\b(the the|a a|of of|in in|is is)\b|"          # doubled function words
    r"\b(is|was|are|were)\s*\?|"                       # trailing copula
    r"\bthe\s+\?|\bof\s+\?|"                           # dangling article/prep
    r"\s{2,}|"                                          # collapsed formatting
    r"\?\?", re.I)


def fold(s):
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def sig(s):
    return set(fold(s).split()) - STOP


# What KIND of thing an option is, from the corpus's own description. Comparing
# only number-vs-text missed the loudest giveaway there is: a question about a
# "shrub of the dogbane family" offering Myrtle, Nerium, Date palm and European
# HORNET. Three plants and an insect — nobody needs to know the fact.
SUBJECT_KIND = [
    ("plant",   r"\b(plant|shrub|tree|flower|grass|fern|moss|herb|vine|genus of plants|"
                r"flowering plant|conifer|palm|cactus)\b"),
    ("animal",  r"\b(insect|bird|mammal|fish|reptile|amphibian|spider|beetle|wasp|hornet|"
                r"moth|butterfly|species of animal|genus of|dinosaur|crustacean|mollusc)\b"),
    ("person",  r"\b(born \d{4}|\(\d{4}[–-]|politician|footballer|actor|actress|singer|"
                r"writer|player|physicist|philosopher|emperor|monarch|composer|director)\b"),
    ("place",   r"\b(country|city|town|village|island|river|mountain|region|province|"
                r"capital|lake|desert|county|municipality|state in)\b"),
    ("work",    r"\b(film|movie|song|album|novel|book|poem|series|sitcom|anime|video game|"
                r"painting|opera|symphony|manga|sculpture)\b"),
    ("org",     r"\b(company|corporation|club|team|university|bank|airline|band|agency|"
                r"party|organisation|organization|brand)\b"),
    ("event",   r"\b(battle|war\b|siege|revolution|treaty|massacre|disaster|earthquake|"
                r"eruption|pandemic|election)\b"),
    ("chemical", r"\b(chemical element|compound|molecule|protein|enzyme|mineral|isotope)\b"),
    ("disease", r"\b(disease|disorder|syndrome|infection|cancer|virus|bacterium)\b"),
]
SUBJECT_KIND = [(n, re.compile(p, re.I)) for n, p in SUBJECT_KIND]


def subject_kind(name, desc):
    d = desc.get(name, "")
    for n, rx in SUBJECT_KIND:
        if rx.search(d):
            return n
    return None


def kind_of(opt):
    f = fold(opt)
    if YEAR.match(f):
        return "year"
    if NUM.match(f.replace(" ", "")):
        return "number"
    return "text"


def load():
    rows = json.loads((A / "corpus.json").read_text())["questions"]
    years, occ, desc = {}, {}, {}
    ents = json.loads((A / "enrich.json").read_text())["entities"]
    for t, e in ents.items():
        b = e.get("numbers", {}).get("birth_year")
        if b:
            years[t.replace("_", " ")] = int(b["value"])
    OCC = re.compile(
        r"\b(ski jumper|footballer|basketball player|baseball player|tennis player|"
        r"golfer|boxer|sprinter|swimmer|cyclist|athlete|racing driver|actor|actress|"
        r"singer|musician|composer|rapper|novelist|poet|writer|author|playwright|"
        r"philosopher|painter|sculptor|architect|physicist|chemist|biologist|"
        r"mathematician|astronomer|engineer|inventor|economist|politician|president|"
        r"prime minister|king|queen|emperor|monarch|general|film director|filmmaker|"
        r"screenwriter|journalist|businessman|entrepreneur)\b", re.I)
    for q in rows:
        e = q[6] or ""
        if ":" in e and "→" not in e:
            _, d = e.split(":", 1)
            d = d.strip()
            if d and len(d) > 8 and not d[0].isdigit():
                desc.setdefault(q[7], d)
    for name, d in desc.items():
        m = OCC.search(d)
        if m:
            occ[name] = m.group(1).lower()
    return rows, years, occ, desc


def eliminable(q, years, occ, desc):
    """How many distractors a player can discard knowing nothing (0-3)."""
    opts, ci = q[2], q[3]
    if not opts or len(opts) < 4 or not (0 <= ci < len(opts)):
        return 0, []
    answer = str(opts[ci])
    others = [str(o) for i, o in enumerate(opts) if i != ci]
    why = []
    out = 0
    for o in others:
        reasons = []
        if kind_of(o) != kind_of(answer):
            reasons.append("type")
        ya, yo = years.get(answer), years.get(o)
        if ya and yo and abs(ya - yo) > 400:
            reasons.append("era")
        oa, oo = occ.get(answer), occ.get(o)
        if oa and oo and oa != oo:
            reasons.append("domain")
        ka, ko = subject_kind(answer, desc), subject_kind(o, desc)
        if ka and ko and ka != ko:
            reasons.append(f"kind:{ko}-vs-{ka}")
        if len(o) * 2.5 < len(answer) and len(answer) > 25:
            reasons.append("length")
        if reasons:
            out += 1
            why.append(f"{o} [{'+'.join(reasons)}]")
    return out, why


# How many NEW significant words the reveal has to add before it counts as
# teaching something. Zero was too strict: a delight-written clue already names
# half the context, so "Li Peng: Premier of China from 1987 to 1998" scored as
# hollow when the dates are exactly the payoff. Two is the line — one stray word
# is a coincidence of phrasing, a real fact carries more.
HOLLOW_NEW_WORDS = 2


def hollow(q):
    """Does the reveal teach anything the question did not already say?"""
    expl, ans = (q[6] or ""), (q[2][q[3]] if q[2] and 0 <= q[3] < len(q[2]) else "")
    if not expl.strip():
        return True
    body = expl.split(":", 1)[1] if ":" in expl else expl
    body = body.strip()
    if not body:
        return True
    if fold(body) == fold(ans):
        return True                       # "Netflix: United States"
    return len(sig(body) - sig(ans) - sig(q[1])) < HOLLOW_NEW_WORDS


# A chunky option button is about 34 characters wide at the default type size
# before it wraps, and wraps to two lines at most before the row grows.
OPTION_CHARS = 34
UNBREAKABLE = re.compile(r"\S{26,}")          # one token no wrap can split
NON_LATIN = re.compile(r"[\u0590-\u05FF\u0600-\u06FF\u3040-\u30FF"
                       r"\u4E00-\u9FFF\uAC00-\uD7AF]")


def layout_risk(q):
    """How likely is this question to render badly? Higher is worse."""
    prompt, opts = q[1] or "", [str(o) for o in (q[2] or [])]
    if not opts:
        return 0, []
    why, score = [], 0
    longest = max(len(o) for o in opts)
    if longest > OPTION_CHARS * 2:
        score += 3; why.append(f"option {longest} chars")
    elif longest > OPTION_CHARS:
        score += 1; why.append(f"option {longest} chars")
    if sum(len(o) > OPTION_CHARS for o in opts) >= 3:
        score += 2; why.append("three or more long options")
    tok = UNBREAKABLE.search(" ".join(opts + [prompt]))
    if tok:
        score += 3; why.append(f"unbreakable token '{tok.group()[:30]}'")
    if NON_LATIN.search(prompt + " ".join(opts)):
        score += 1; why.append("non-Latin script")
    if len(prompt) > 260:
        score += 1; why.append(f"prompt {len(prompt)} chars")
    return score, why


def audit():
    rows, years, occ, desc = load()
    findings = collections.defaultdict(list)
    stats = collections.Counter()
    for q in rows:
        prompt = q[1] or ""
        n, why = eliminable(q, years, occ, desc)
        stats[f"eliminable_{n}"] += 1
        if n >= 3:
            findings["ELIMINABLE"].append((q[0], prompt, q[2], why))
        if TEMPLATED.match(prompt):
            stats["templated"] += 1
            findings["TEMPLATED"].append((q[0], prompt, q[2], []))
        if hollow(q):
            stats["hollow"] += 1
            findings["HOLLOW"].append((q[0], prompt, q[2], [q[6] or "(none)"]))
        if AWKWARD.search(prompt):
            findings["AWKWARD"].append((q[0], prompt, q[2], []))
        risk, rwhy = layout_risk(q)
        if risk >= 3:
            findings["LAYOUT"].append((q[0], prompt, q[2], rwhy + [f"risk {risk}"]))
    return rows, findings, stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rule")
    ap.add_argument("--show", type=int, default=8)
    ap.add_argument("--ids", nargs=2, metavar=("RULE", "N"))
    a = ap.parse_args()

    rows, findings, stats = audit()
    if a.ids:
        rule, n = a.ids[0], int(a.ids[1])
        print(",".join(f[0] for f in findings.get(rule, [])[:n]))
        return 0

    total = len(rows)
    print(f"{total} questions scored\n")
    for k in range(4):
        c = stats[f"eliminable_{k}"]
        print(f"  {k} of 3 distractors eliminable without knowing the fact: "
              f"{c:>7} ({c / total:.1%})")
    print()
    findings["LAYOUT"].sort(key=lambda f: -int(f[3][-1].split()[-1]))
    for rule in ("ELIMINABLE", "AWKWARD", "HOLLOW", "TEMPLATED", "LAYOUT"):
        f = findings.get(rule, [])
        print(f"{rule:12}{len(f):>7} ({len(f)/total:.1%})")
    print()
    show = [a.rule] if a.rule else ["ELIMINABLE", "AWKWARD"]
    for rule in show:
        print(f"--- {rule} ---")
        for qid, prompt, opts, why in findings.get(rule, [])[:a.show]:
            print(f"   {prompt[:74]}")
            print(f"      {opts}")
            for w in why[:3]:
                print(f"      {w}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
