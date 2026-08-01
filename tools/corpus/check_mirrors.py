#!/usr/bin/env python3
"""Do all three tracked copies of every question file agree?

    python3 tools/corpus/check_mirrors.py        # exits non-zero on drift

`assets/` is what web and Windows read (Windows links `assets/*.json` from its
csproj). `TidbitsTrivia/Resources/` is what iOS, macOS and tvOS bundle.
`android/app/src/main/assets/` is what Android ships. They are supposed to be
byte-identical; nothing enforced it.

On 2026-08-01 they drifted and it was invisible. Checking whether the generators
were safe to re-run, each was invoked as `gen_X.py --out /tmp/test.json` — which
redirects only the assets/ path, because the mirror writes were unconditional. So
the SAFETY CHECK replaced the iOS and Android copies: typeanswer.json became the
33,364-row generated set (dropping 886 authored rows) and oddoneout.json dropped
to 179 (losing all 67 authored ones), while assets/ stayed correct. A `git add
-A` then committed it.

Nothing failed. The app built, 151 tests passed, and 126 playthroughs came back
clean — because the simulator was reading the clobbered iOS copy and every
audit was reading the correct assets/ one. It surfaced only as a contradiction
between two measurements: the play sweep reported typeAnswer x business at 100%
on-category while the file it was checked against had zero business rows.

A cross-platform repo needs the lockstep asserted, not assumed.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIRRORS = {
    "assets":  ROOT / "assets",                                  # web + Windows
    "apple":   ROOT / "TidbitsTrivia" / "Resources",             # iOS/macOS/tvOS
    "android": ROOT / "android" / "app" / "src" / "main" / "assets",
}
FILES = ["corpus.json", "picture.json", "thisorthat.json", "closest.json",
         "order.json", "match.json", "typeanswer.json", "oddoneout.json",
         "enumerate.json", "difficulty.json", "enrich.json"]


def summary(path):
    if not path.exists():
        return None
    raw = path.read_bytes()
    try:
        d = json.loads(raw)
        count = d.get("count", len(d.get("questions", [])))
    except json.JSONDecodeError:
        count = "?"
    return count, hashlib.md5(raw).hexdigest()[:12]


def main():
    bad = 0
    for name in FILES:
        seen = {k: summary(d / name) for k, d in MIRRORS.items()}
        present = {k: v for k, v in seen.items() if v}
        if len(present) < 2:
            continue   # single-home files are fine
        digests = {v[1] for v in present.values()}
        ok = len(digests) == 1
        mark = "ok  " if ok else "DRIFT"
        detail = "  ".join(f"{k}={v[0]}" for k, v in present.items())
        print(f"{mark} {name:18} {detail}")
        if not ok:
            bad += 1
    if bad:
        print(f"\n{bad} file(s) differ between platforms. Regenerate from one source, or "
              f"restore the odd one out — do NOT hand-edit a mirror.")
        return 1
    print(f"\nall {len(FILES)} question files identical across web/Windows, Apple and Android")
    return 0


if __name__ == "__main__":
    sys.exit(main())
