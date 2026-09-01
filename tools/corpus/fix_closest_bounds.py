"""Give the Closest Call slider bounds worth dragging.

Rendered a round and read it: "In what year did Carole Lombard die?" over a
slider running 1000 to 2025, opening at 1513. She died in 1942. The player is
asked to drag through a millennium to place a Hollywood actress, and the whole
20th century occupies 9% of the track.

Measuring turned a usability complaint into a scoring bug. 2,500 of the 2,683
rows share that one slider, and because almost every subject is modern the answer
sits at a median 0.93 of the track. So:

    always guess 1985, never move the slider -> scores on 61.7% of the mode

That is the mode farmable by a player who knows nothing, which is worse than the
dragging.

The repair gives each row its own window around its answer:

  * width 120 for a year, so the era is legible but the decade is still a real
    estimate; tolerance 5 (4.2% of the window, close to the 3.9% the old 40/1025
    implied, so a knowledgeable player is no worse off)
  * the answer is placed at a position derived from the row id, kept away from
    the middle, because the slider OPENS at the midpoint — centring the window on
    the answer would hand out the points it just stopped giving away
  * elevation and atomic-number rows keep their natural domain, which is already
    the real range of the quantity

    python3 tools/corpus/fix_closest_bounds.py [--apply]

Then run tools/corpus/resync_corpus.sh.
"""
import argparse
import collections
import hashlib
import json
import pathlib
import sys


def corpus_version(body: str) -> str:
    """The content hash export_json.py writes. Recomputed on EVERY write.

    Preserving the old string was a real, shipped bug: three consecutive
    commits shipped 110,618 -> 110,541 -> 110,512 questions all under version
    f3c1477ed04a, so every web player who had already cached the corpus kept
    serving the rows those repairs removed. The web client busts its
    IndexedDB cache on this string and nothing else."""
    return hashlib.md5(body.encode()).hexdigest()[:12]


ROOT = pathlib.Path(__file__).resolve().parents[2]
CLOSEST = ROOT / "assets" / "closest.json"

YEAR_KINDS = {"birth_year", "death_year", "inception"}
WIDTH = 120
TOLERANCE = 5
# Keep the answer out of the middle fifth: the slider opens at the midpoint, so
# an answer sitting there is a point for doing nothing.
LOW, HIGH, DEAD_LO, DEAD_HI = 0.12, 0.88, 0.42, 0.58


def position(row_id):
    """A stable position in [LOW, HIGH] avoiding the dead centre."""
    h = int(hashlib.sha1(row_id.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF
    p = LOW + h * (HIGH - LOW)
    if DEAD_LO <= p <= DEAD_HI:
        p = DEAD_LO - (p - DEAD_LO) if h < 0.5 else DEAD_HI + (DEAD_HI - p)
        p = min(max(p, LOW), HIGH)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    data = json.loads(CLOSEST.read_text())
    rows = data["questions"]

    changed = 0
    examples = []
    for r in rows:
        kind = r[0].split(":")[1] if ":" in r[0] else ""
        if kind not in YEAR_KINDS:
            continue
        answer = r[2]
        p = position(r[0])
        lo = int(round(answer - p * WIDTH))
        hi = lo + WIDTH
        # Never claim a year the corpus cannot contain.
        if hi > 2025:
            hi, lo = 2025, 2025 - WIDTH
        before = (r[3], r[4], r[6])
        r[3], r[4], r[6] = lo, hi, TOLERANCE
        changed += 1
        if len(examples) < 6:
            examples.append((str(r[1])[:52], answer, before, (lo, hi, TOLERANCE)))

    print(f"year sliders rebounded: {changed} of {len(rows)}")
    for prompt, ans, b, n in examples:
        print(f"   {prompt:54} answer {ans}\n      was {b[0]}..{b[1]} tol {b[2]}   now {n[0]}..{n[1]} tol {n[2]}")

    # The measurement that motivated this, re-run on the result.
    yr = [r for r in rows if (r[0].split(":")[1] if ":" in r[0] else "") in YEAR_KINDS]
    best, score = None, 0
    for g in range(1000, 2026):
        s = sum(1 for r in yr if abs(g - r[2]) <= r[6])
        if s > score:
            best, score = g, s
    print(f"\nbest single fixed guess now: {best} scores {score / len(yr):.1%} "
          f"of year questions (was 61.7%)")
    # And the midpoint, which is where the slider opens.
    mid = sum(1 for r in yr if abs((r[3] + r[4]) / 2 - r[2]) <= r[6])
    print(f"leaving the slider untouched at its midpoint: {mid / len(yr):.1%}")

    if not a.apply:
        print("\n(dry run — pass --apply to write, then run resync_corpus.sh)")
        return 0
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    CLOSEST.write_text(
        f'{{"version":"{corpus_version(body)}","count":{len(rows)},"questions":{body}}}')
    print(f"\nwrote {CLOSEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
