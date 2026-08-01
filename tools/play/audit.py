#!/usr/bin/env python3
"""Audit the questions a real play sweep delivered.

    tools/play/sweep.sh 1000              # drive the simulator, writes play.jsonl
    python3 tools/play/audit.py play.jsonl [--full] [--rule D1]

Reads the JSONL emitted by `QuestionProvider.sweepPlay` (the shipped assembly,
driven on a simulator) and applies the checks below. Split this way on purpose:
the sweep must run inside the app to be honest about what a player receives, but
the RULES want to change twenty times an hour, and rebuilding the app for each
one is how an audit ends up with three rules instead of thirty.

Findings are grouped: structural (S) = broken, distractor (D) = guessable or
unfair, round (R) = a property of the assembled round rather than any one row,
experience (E) = it works but it is not enjoyable.
"""
import argparse
import collections
import json
import re
import sys
import unicodedata

# ---------------------------------------------------------------- helpers

STOP = {"the", "a", "an", "of", "in", "on", "at", "to", "and", "or", "for",
        "is", "was", "were", "by", "with", "from", "as", "that", "this",
        "which", "who", "what", "it", "its", "his", "her", "their"}


def fold(s):
    """Lowercase, strip accents and punctuation — the same shape of comparison
    the app's matcher uses, so 'Beyoncé' and 'Beyonce' are one string."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).strip()


def words(s):
    return [w for w in fold(s).split() if w and w not in STOP]


NUM_RE = re.compile(r"^-?[\d,]+(\.\d+)?$")
YEAR_RE = re.compile(r"^-?\d{3,4}(\s*(bc|bce|ad|ce))?$")


def shape_of(opt):
    """A coarse type for an option. Distractors that are a DIFFERENT type from
    the answer are the loudest giveaway in multiple choice — if three options are
    people and one is a year, nobody needs to know the fact.

    Only WHOLLY numeric options count as a different type. An earlier version gave
    anything containing a digit its own class, which flagged 'Hannover 96' among
    football clubs and 'The Equalizer 3' among films — a digit inside a name is
    not a tell, and 85 findings of that kind buried the real ones."""
    f = fold(opt)
    if not f:
        return "empty"
    if YEAR_RE.match(f):
        return "year"
    if NUM_RE.match(f.replace(" ", "")):
        return "number"
    return "text"


# Which shape field each mode REQUIRES to render as itself. A Closest Call
# question with no `closest` spec falls back to a plain MCQ — the mode silently
# stops being the mode, which no unit test on the corpus can see.
MODE_SHAPE = {
    "closestCall": "closest",
    "ordering": "ordering",
    "matching": "matching",
    "typeAnswer": "accepted",
    "enumerate": "enumerate",
    "pictureId": "image",
}

# Modes whose delivered count is legitimately not `questionCount`.
# timeAttack/survival are clock- and life-bounded (99 is a sentinel, not a target).
UNBOUNDED = {"timeAttack", "survival"}


# Birth years for the corpus's people, loaded once from the enrichment file when
# it is beside the sweep. Absent it, the era rule simply does not fire.
_YEARS = None


def _birth_year(name):
    global _YEARS
    if _YEARS is None:
        _YEARS = {}
        try:
            import pathlib
            root = pathlib.Path(__file__).resolve().parents[2]
            ents = json.loads((root / "assets" / "enrich.json").read_text())["entities"]
            for t, e in ents.items():
                b = e.get("numbers", {}).get("birth_year")
                if b:
                    _YEARS[t.replace("_", " ")] = int(b["value"])
        except Exception:
            _YEARS = {}
    return _YEARS.get(name)


def load(path):
    games, rows = collections.OrderedDict(), []
    meta = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.replace("\r", "")
            if "PLAY-GAME\t" in line:
                p = line.split("PLAY-GAME\t", 1)[1].split("\t")
                if len(p) >= 5:
                    games[int(p[0])] = {"mode": p[1], "cat": p[2],
                                        "got": int(p[3]), "want": int(p[4])}
            elif "PLAY-Q\t" in line:
                try:
                    rows.append(json.loads(line.split("PLAY-Q\t", 1)[1]))
                except json.JSONDecodeError:
                    meta.setdefault("unparsed", 0)
                    meta["unparsed"] += 1
    return games, rows, meta


# ---------------------------------------------------------------- rules

def audit(games, rows):
    """Yield (rule, severity, key, detail). `key` dedupes a finding that recurs
    across games so a single bad row is not reported four hundred times."""
    out = []

    def add(rule, sev, key, detail):
        out.append((rule, sev, key, detail))

    by_game = collections.defaultdict(list)
    for r in rows:
        by_game[r["game"]].append(r)

    # ---- per question ------------------------------------------------
    for r in rows:
        qid, prompt = r["id"], r.get("prompt", "")
        opts = r.get("options") or []
        ci = r.get("correct", -1)
        ans = r.get("answer", "")
        mode = r["mode"]
        need_shape = MODE_SHAPE.get(mode)
        is_shaped = need_shape is not None and r.get(need_shape)

        # S — structural
        if not prompt.strip():
            add("S1", "broken", qid, "empty prompt")
        if re.search(r"%@|%\d*\$?[sd]|\{\}|\bnil\b|Optional\(|\bNaN\b", prompt):
            add("S2", "broken", qid, f"unresolved placeholder: {prompt[:90]}")
        # Shape modes legitimately carry no options; MCQ modes must have 4.
        if not is_shaped:
            if len(opts) < 2:
                add("S3", "broken", qid, f"{len(opts)} options: {prompt[:70]}")
            elif not (0 <= ci < len(opts)):
                add("S4", "broken", qid, f"correctIndex {ci} of {len(opts)}")
            if any(not str(o).strip() for o in opts):
                add("S5", "broken", qid, f"blank option in {opts}")
        if need_shape and not r.get(need_shape):
            add("S6", "broken", f"{mode}:{qid}",
                f"{mode} question has no `{need_shape}` — renders as a plain MCQ")

        # D — distractors
        if opts and not is_shaped:
            folded = [fold(str(o)) for o in opts]
            dupes = [o for o, n in collections.Counter(folded).items() if n > 1 and o]
            if dupes:
                add("D1", "unfair", qid, f"duplicate options {dupes} in {opts}")
            # A binary "which came first?" has only two options, so "the answer is
            # the only X" is arithmetic, not a tell — it is true of one side of
            # every pair. Needs three or more before the odd-one-out reads as a hint.
            if 0 <= ci < len(opts) and len(opts) >= 3:
                shapes = [shape_of(str(o)) for o in opts]
                other = [s for i, s in enumerate(shapes) if i != ci]
                if other and shapes[ci] not in other and len(set(other)) == 1:
                    add("D2", "unfair", qid,
                        f"answer is the only `{shapes[ci]}` among {other[0]}: {opts}")
                lens = [len(str(o)) for o in opts]
                others = [l for i, l in enumerate(lens) if i != ci]
                # Individually noticeable, but NOT a pattern a player can play:
                # measured over all 128,638 corpus MCQs the answer is the single
                # longest option 24.2% of the time, against a 25% chance baseline,
                # and only 0.23% are this extreme. Kept as a per-question smell,
                # deliberately not treated as a systematic tell worth a risky
                # distractor-swap across the corpus.
                if others and lens[ci] > 2.5 * max(others) and lens[ci] > 25:
                    add("D3", "unfair", qid,
                        f"answer {lens[ci]} chars vs longest distractor {max(others)}: {opts}")
                # The answer spelled out inside the prompt.
                aw = set(words(ans))
                if aw and aw.issubset(set(words(prompt))) and len(fold(ans)) > 3:
                    add("D4", "unfair", qid,
                        f"prompt contains its own answer '{ans}': {prompt[:80]}")

        # D5 — every option is a person, but they are centuries apart.
        #
        # Found by LOOKING at the longest prompt rather than counting it: a clue
        # about a living Russian-British activist sat beside Amin al-Husseini,
        # Lazarus of Bethany and Titus. The era in the clue eliminates three
        # options before any knowledge is applied. Measured over the corpus, 445
        # of 4,858 MCQs whose four options are all dated people (9.2%) span more
        # than 400 years — the worst is 4,314. Reported, not yet fixed: the fix is
        # era-aware distractor selection at generation time.
        if opts and not is_shaped and 0 <= ci < len(opts):
            yrs = [_birth_year(str(o)) for o in opts]
            if all(yrs) and max(yrs) - min(yrs) > 400:
                add("D5", "unfair", qid,
                    f"options span {max(yrs) - min(yrs)} years: {opts}")

        # E — experience
        #
        # Name as Many is exempt: its reveal card renders the whole set with the
        # ones you named marked and the ones you missed left blank ("You named 3
        # of 4"), which IS the learning payload for that mode. The rule flagged
        # all 81 of them as missing a "learn the fact" string, I read the live
        # panel, concluded the missed items were never shown, and rewrote it —
        # then the screenshot showed the reveal card doing it already, one card
        # down. Verify on screen before believing an audit about the screen.
        if r["mode"] != "enumerate" and not (r.get("explanation") or "").strip():
            add("E1", "quality", qid, f"no explanation: {prompt[:70]}")
        # 220 was a guess and it was wrong. The LONGEST prompt in the corpus (289
        # chars, src:describe:Vladimir_Kara-Murza) was rendered on an iPhone 17 Pro
        # via TIDBITS_QUESTION: it wraps cleanly inside the card with all four
        # options still on screen and nothing truncated. Median prompt is 41 chars,
        # p90 is 191. Raised to a length the card genuinely cannot hold, so the
        # rule stops reporting 131 well-written clues as a defect.
        if len(prompt) > 340:
            add("E2", "quality", qid, f"{len(prompt)}-char prompt: {prompt[:70]}...")
        for o in opts:
            if len(str(o)) > 90:
                add("E3", "quality", qid, f"{len(str(o))}-char option: {str(o)[:70]}...")

    # ---- per round ---------------------------------------------------
    for g, qs in by_game.items():
        info = games.get(g, {})
        mode, cat = info.get("mode", qs[0]["mode"]), info.get("cat", "?")
        tag = f"{mode}/{cat}"

        ids = [q["id"] for q in qs]
        rep = [i for i, n in collections.Counter(ids).items() if n > 1]
        if rep:
            add("R1", "broken", f"{tag}:dup", f"game {g} repeats question {rep}")

        # The shape modes share a generic PROMPT by design — "Put these in order,
        # earliest first" is a rubric, not the question; the content lives in the
        # `ordering`/`matching`/`enumerate` payload. Comparing prompts alone
        # reported every one of those rounds as asking the same thing twice, so the
        # key has to include the payload.
        # thisOrThat and oddOneOut share a stem too ("Which came first?"), and
        # their content is the OPTIONS — so the key needs those as well, or every
        # binary round reports as asking the same question ten times.
        def content_key(q):
            shape = MODE_SHAPE.get(q["mode"])
            payload = json.dumps(q.get(shape), sort_keys=True) if shape else ""
            opts = json.dumps(sorted(str(o) for o in (q.get("options") or [])))
            return fold(q.get("prompt", "")) + "|" + payload + "|" + opts

        pf = [content_key(q) for q in qs]
        prep = [p for p, n in collections.Counter(pf).items() if n > 1 and p.strip("|")]
        if prep and not rep:
            add("R2", "broken", f"{tag}:dupprompt",
                f"game {g} asks the same question twice: {prep[0][:70]}")

        want, got = info.get("want", 0), info.get("got", len(qs))
        if mode not in UNBOUNDED and want and got < want:
            add("R3", "broken", f"{tag}:short",
                f"{tag} delivered {got} of {want} questions")
        if got == 0:
            add("R4", "broken", f"{tag}:empty", f"{tag} delivered NO questions")

        titles = collections.Counter(q.get("title", "") for q in qs)
        for t, n in titles.items():
            if t and n >= 3 and n > len(qs) / 3:
                add("R5", "quality", f"{tag}:{t}",
                    f"{n} of {len(qs)} questions in one {tag} round are about '{t}'")

        answers = collections.Counter(fold(q.get("answer", "")) for q in qs if q.get("answer"))
        for a, n in answers.items():
            if a and n >= 3:
                add("R6", "quality", f"{tag}:ans:{a}",
                    f"'{a}' is the answer {n} times in one {tag} round")

        # A round that never leaves the picked category is the promise; one that
        # wanders out of it is the bug.
        if cat != "mixed":
            stray = [q for q in qs if q.get("qcat") and q["qcat"] != cat]
            if stray and len(stray) > len(qs) / 2:
                add("R7", "quality", f"{tag}:stray",
                    f"{len(stray)}/{len(qs)} questions in a {cat} round are not {cat} "
                    f"({collections.Counter(q['qcat'] for q in stray).most_common(3)})")

    # ---- across the whole sweep -------------------------------------
    mcq = [r for r in rows if (r.get("options") and not MODE_SHAPE.get(r["mode"]))]
    if mcq:
        pos = collections.Counter(r.get("correct") for r in mcq)
        top, n = pos.most_common(1)[0]
        share = n / len(mcq)
        if share > 0.40:
            add("R8", "unfair", "answerpos",
                f"the answer is at index {top} in {share:.0%} of {len(mcq)} MCQs "
                f"(even would be ~25%) — position is a tell")
    return out


# ---------------------------------------------------------------- report

SEV_ORDER = {"broken": 0, "unfair": 1, "quality": 2}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--full", action="store_true", help="every instance, not a sample")
    ap.add_argument("--rule", help="only this rule")
    a = ap.parse_args()

    games, rows, meta = load(a.path)
    if not rows:
        print(f"no questions in {a.path} — did the sweep run?")
        return 1

    findings = audit(games, rows)
    if a.rule:
        findings = [f for f in findings if f[0] == a.rule]

    print(f"{len(games)} games, {len(rows)} questions delivered")
    if meta.get("unparsed"):
        print(f"  WARNING {meta['unparsed']} lines failed to parse")

    combos = collections.Counter((g["mode"], g["cat"]) for g in games.values())
    print(f"  {len(combos)} distinct mode x category combinations covered")

    by_rule = collections.defaultdict(list)
    for rule, sev, key, detail in findings:
        by_rule[(sev, rule)].append((key, detail))

    if not by_rule:
        print("\nno findings")
        return 0

    print()
    total_unique = 0
    for (sev, rule) in sorted(by_rule, key=lambda k: (SEV_ORDER[k[0]], k[1])):
        items = by_rule[(sev, rule)]
        uniq = {}
        for key, detail in items:
            uniq.setdefault(key, detail)
        total_unique += len(uniq)
        print(f"[{sev.upper():8}] {rule}  {len(uniq)} distinct ({len(items)} occurrences)")
        show = list(uniq.values()) if a.full else list(uniq.values())[:4]
        for d in show:
            print(f"           {d}")
        if not a.full and len(uniq) > 4:
            print(f"           ... and {len(uniq) - 4} more (--rule {rule} --full)")
        print()

    print(f"{total_unique} distinct findings across {len(by_rule)} rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
