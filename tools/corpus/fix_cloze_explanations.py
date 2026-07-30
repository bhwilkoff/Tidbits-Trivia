#!/usr/bin/env python3
"""Restore the natural lead sentence in redacted explanations.

The reveal card renders the explanation AFTER the answer is already shown, but tens of
thousands of cloze-derived rows stored it as `"<answer> — ____<rest>"` — the answer redacted
out of its own Wikipedia lead sentence. That redaction only ever mattered *before* the reveal,
so on screen it read as a bug:

    AS Roma — ____ (Rome Sport Association; Italian) is a professional football club …

The fix drops the redundant `"<answer> — ____"` head and keeps the answer, restoring the
sentence Wikipedia actually opens with:

    AS Roma (Rome Sport Association; Italian) is a professional football club …

Only EXPLANATION columns are touched. A `____` in a *prompt* is the game — both the
fill-in-the-blank corpus rows and Type-Answer blank the answer on purpose — and is left
strictly alone. corpus.json was not the only offender: picture.json and typeanswer.json carry
the same explanations, which is why a first pass looked clean and the app still showed a gap.

Idempotent — rows without the marker are untouched, so re-running is a no-op.

    python3 tools/corpus/fix_cloze_explanations.py [--check]

`--check` exits non-zero if any explanation still OPENS with the redaction (the visible bug).
Rows carrying a second blank deeper in the body are reported but tolerated: the cloze redacted
a sub-word of the answer ("Fishing cat — ____ … is a medium-sized wild ____ of South Asia"
blanked "cat"), which token is not recoverable, and substituting the whole answer would read
"a medium-sized wild Fishing cat". Guessing there would corrupt real content.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# (filename, explanation column, answer column).
DATASETS = [
    ("corpus.json", 6, 7),
    ("picture.json", 6, 7),
    ("typeanswer.json", 5, 2),
]
# assets/ is the source of truth; the rest are platform mirrors/fixtures that ship their own
# copy, so all of them have to be repaired (and stay repaired).
MIRROR_DIRS = [
    ROOT / "assets",
    ROOT / "TidbitsTrivia" / "Resources",
    ROOT / "android" / "app" / "src" / "main" / "assets",
    ROOT / "windows" / "Tidbits.HeadlessTests" / "Fixtures",
]


def restore(answer: str, explanation: str) -> str:
    head = f"{answer} — ____"
    return answer + explanation[len(head):] if explanation.startswith(head) else explanation


def rows_of(data):
    return data["questions"] if isinstance(data, dict) and "questions" in data else data


def process(path: pathlib.Path, expl_i: int, ans_i: int, check_only: bool) -> int:
    if not path.exists():
        return 0
    data = json.loads(path.read_text())
    rows = rows_of(data)

    # A row is a FAILURE only if restoring it would produce clean text — i.e. it should have
    # been fixed and wasn't. Rows whose body carries a second blank are deliberately deferred.
    fixable, deferred = [], []
    for r in rows:
        before = r[expl_i] or ""
        if "____" not in before:
            continue
        after = restore(r[ans_i] or "", before)
        (deferred if (after == before or "____" in after) else fixable).append(r)

    label = f"{path.parent.name}/{path.name}"
    if check_only:
        if fixable:
            print(f"FAIL {label}: {len(fixable)} explanation(s) still open with the redaction")
            for r in fixable[:3]:
                print("  ", r[0], "|", (r[expl_i] or "")[:100])
            return 1
        note = f"; {len(deferred)} deferred (a second blank in the body)" if deferred else ""
        print(f"OK   {label}: no redacted openings ({len(rows)} rows{note})")
        return 0

    fixed = 0
    for r in fixable:
        after = restore(r[ans_i] or "", r[expl_i] or "")
        if after != after.strip() or "  " in after:
            print(f"REFUSING: {r[0]} would produce malformed text: {after[:120]!r}")
            return 1
        r[expl_i] = after
        fixed += 1

    # Second, strictly-safe pass over the deferred rows: when the answer is a SINGLE WORD,
    # any remaining blank can only ever be that word, so substituting it is deterministic
    # rather than a guess. Multi-word answers stay deferred — "Piri Reis" would turn
    # "(born Muhiddin ____)" into "(born Muhiddin Reis)", and a plausible-but-wrong fact is
    # worse than a visible gap.
    resolved = 0
    for r in list(deferred):
        answer = (r[ans_i] or "").strip()
        if len(answer.split()) != 1 or not answer:
            continue
        after = restore(answer, r[expl_i] or "")
        # Mid-sentence occurrences are common nouns, so match the surrounding case.
        head, sep, tail = after.partition("____")
        while sep:
            token = answer if (not head.strip() or head.rstrip().endswith((".", ":", "\u2014"))) else answer.lower()
            after = head + token + tail
            head, sep, tail = after.partition("____")
        if "____" in after or after != after.strip() or "  " in after:
            continue
        r[expl_i] = after
        deferred.remove(r)
        resolved += 1
    fixed += resolved

    if fixed:
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    note = f" ({len(deferred)} deferred — multi-word answer, ambiguous)" if deferred else ""
    print(f"{label}: restored {fixed} of {len(rows)}{note}")
    return 0


def main() -> int:
    check_only = "--check" in sys.argv
    worst = 0
    for name, expl_i, ans_i in DATASETS:
        for d in MIRROR_DIRS:
            worst = max(worst, process(d / name, expl_i, ans_i, check_only))
    return worst


if __name__ == "__main__":
    sys.exit(main())
