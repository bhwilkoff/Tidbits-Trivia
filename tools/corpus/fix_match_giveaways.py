#!/usr/bin/env python3
"""Strip Match-Up keys whose disambiguating parenthetical contains the answer.

Found by play-testing the Match-Up mode on the iPhone simulator: a round showed

    Magnificat (Bach)          ->  Johann Sebastian Bach
    Symphony No. 3 (Górecki)   ->  Henryk Górecki

Two of the four pairs were free, because the parenthetical added to make the WORK
title unique also names its composer — which is the value the player is matching to.
Same class as the MCQ option-disambiguator giveaway `recategorize_and_clean.py`
already fixes ("John Thomson (photographer)" beside bare names).

The fix drops the parenthetical, but only when the stripped key stays UNIQUE within
its row — the parenthetical is there for disambiguation, and collapsing two keys to
the same text would make the row unanswerable. A row that cannot be fixed safely is
reported and left alone rather than half-repaired.

Deliberately NOT touched:
  * key and value being the same name (San Marino -> San Marino, Monaco -> Monaco).
    That is a true fact about city-states and still requires knowing it.
  * partial overlaps that need real knowledge (Tunisia -> Tunis, El Salvador ->
    San Salvador, Saudi Arabia -> Saudi riyal).

    python3 tools/corpus/fix_match_giveaways.py [--check]

`--check` exits non-zero if any leaking key remains.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = [
    ROOT / "assets" / "match.json",
    ROOT / "TidbitsTrivia" / "Resources" / "match.json",
    ROOT / "android" / "app" / "src" / "main" / "assets" / "match.json",
    ROOT / "windows" / "Tidbits.HeadlessTests" / "Fixtures" / "match.json",
]
KEYS_I, VALS_I = 2, 3


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def leaks(key: str, value: str) -> bool:
    """True when the key's PARENTHETICAL hands over the value."""
    inner = " ".join(re.findall(r"\(([^)]*)\)", key))
    if not inner:
        return False
    tokens = [t for t in norm(value).split() if len(t) >= 4]
    return bool(tokens) and any(t in norm(inner) for t in tokens)


def rows_of(data):
    return data["questions"] if isinstance(data, dict) and "questions" in data else data


def repair(rows) -> tuple[int, list[str]]:
    fixed, refused = 0, []
    for row in rows:
        keys, vals = row[KEYS_I], row[VALS_I]
        for i, (k, v) in enumerate(zip(keys, vals)):
            if not leaks(k, v):
                continue
            stripped = re.sub(r"\s*\([^)]*\)", "", k).strip()
            others = [norm(x) for j, x in enumerate(keys) if j != i]
            if not stripped or norm(stripped) in others:
                refused.append(f"{row[0]}: {k!r} -> {v!r} (stripping would collide)")
                continue
            keys[i] = stripped
            fixed += 1
    return fixed, refused


def main() -> int:
    check = "--check" in sys.argv
    total, all_refused = 0, []
    for path in MIRRORS:
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        fixed, refused = repair(rows_of(data))
        all_refused += refused
        total += fixed
        label = f"{path.parent.name}/{path.name}"
        if check:
            print(("FAIL " if fixed else "OK   ") + f"{label}: {fixed} leaking key(s)")
        else:
            if fixed:
                path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
            print(f"{label}: stripped {fixed}")

    for r in dict.fromkeys(all_refused):
        print(f"  REFUSED {r}")
    if check and total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
