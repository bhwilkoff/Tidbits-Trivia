"""Which surfaces can this testing system actually REACH, per platform?

A harness can only assert about a screen it can open. Every gap here is a surface
that is not failing — it is unasked, which reads identically in a green report and
is strictly worse, because a gap in coverage looks like a pass.

This reads the four codebases for the launch hooks each one honours and prints the
matrix, so "everything can be driven" is a measured claim rather than a hope.

    python3 tools/hook_coverage.py
"""
import re
import pathlib
import collections

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Each platform: where its hooks live, and how a hook name appears there.
SOURCES = {
    "apple":   (["TidbitsTrivia"], r'environment\["(TIDBITS_[A-Z_]+)"\]', {".swift"}),
    "android": (["android/app/src/main"], r'"(tidbits_[a-z_]+)"', {".kt"}),
    "windows": (["windows/Tidbits.App", "windows/Tidbits.Core"],
                r'GetEnvironmentVariable\("(TIDBITS_[A-Z_]+)"\)', {".cs"}),
    "web":     (["js"], r"#/([a-z]+)", {".js"}),
}
SKIP = {"bin", "obj", "artifacts", "publish", "node_modules", ".git"}

# The canonical hook per capability, in the Apple spelling. Android/Windows names
# are derived; the web is a route, since its "hook" is the URL.
CAPABILITIES = [
    ("open a tab/section",     "TIDBITS_TAB",          "tidbits_tab",          "TIDBITS_TAB",       "home"),
    ("skip the walkthrough",   "TIDBITS_SKIP_ONBOARD", "tidbits_skip_onboard", "TIDBITS_SKIP_ONBOARD", None),
    ("start a round",          "TIDBITS_AUTOPLAY",     "tidbits_autoplay",     "TIDBITS_AUTOPLAY",  "daily"),
    ("answer automatically",   "TIDBITS_AUTOPILOT",    "tidbits_autopilot",    "TIDBITS_AUTOPILOT", None),
    ("host Tidbits Live",      "TIDBITS_LIVE_HOST",    "tidbits_live_host",    "TIDBITS_LIVE_HOST", "live"),
    ("host a Trivia Night",    "TIDBITS_NIGHT_HOST",   "tidbits_night_host",   "TIDBITS_NIGHT_HOST", "live"),
    ("join a room by code",    "TIDBITS_LIVE_JOIN",    "tidbits_live_join",    "TIDBITS_LIVE_JOIN", "live"),
    ("join under a set name",  "TIDBITS_LIVE_NAME",    "tidbits_live_name",    "TIDBITS_LIVE_NAME", None),
    ("open Settings",          "TIDBITS_SETTINGS",     "tidbits_open",         "TIDBITS_SETTINGS",  "profile"),
    ("open the Club paywall",  "TIDBITS_PAYWALL",      "tidbits_open",         "TIDBITS_PAYWALL",   None),
    ("grant Club entitlement", "TIDBITS_CLUB",         "tidbits_club",         "TIDBITS_CLUB",      None),
    ("open Pass & Play",       "TIDBITS_PARTY",        "tidbits_party",        "TIDBITS_PARTY",     None),
    ("seed records",           "TIDBITS_SEED_RECORDS", "tidbits_seed_records", "TIDBITS_SEED_RECORDS", None),
]


def harvest(platform):
    dirs, pattern, exts = SOURCES[platform]
    found = collections.Counter()
    rx = re.compile(pattern)
    for d in dirs:
        base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.suffix not in exts or not p.is_file():
                continue
            if SKIP & set(p.relative_to(base).parts):
                continue
            for m in rx.findall(p.read_text(errors="ignore")):
                found[m] += 1
    return found


def main():
    have = {p: harvest(p) for p in SOURCES}
    cols = ["apple", "android", "windows", "web"]
    print(f"{'capability':24} " + " ".join(f"{c:>8}" for c in cols))
    print("-" * 24 + " " + " ".join("-" * 8 for _ in cols))
    gaps = []
    for label, ap, an, wi, web in CAPABILITIES:
        row, keys = [], {"apple": ap, "android": an, "windows": wi, "web": web}
        for c in cols:
            k = keys[c]
            ok = bool(k) and have[c].get(k, 0) > 0
            row.append("  yes   " if ok else ("   -    " if k is None else "   NO   "))
            if k is not None and not ok:
                gaps.append((label, c, k))
        print(f"{label:24} " + " ".join(row))
    print(f"\n{len(gaps)} surface(s) this system cannot reach:")
    for label, c, k in gaps:
        print(f"  {c:8} {label:24} (needs {k})")
    print("\n'-' = no equivalent on that platform. 'NO' = the capability exists in the "
          "app but nothing can drive it, so it is untested and reads as a pass.")


if __name__ == "__main__":
    main()
