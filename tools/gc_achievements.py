#!/usr/bin/env python3
"""Create the nine Game Center achievements from docs/GAME-CENTER-SETUP.md §3.

The doc has been a paste-ready table for weeks and nobody pasted it, because it is
nine achievements x (create + localize + image) of identical form-filling. The API
does it in one pass and, unlike the console, is idempotent: anything already there
is left alone and reported, so a re-run after a partial failure is safe.

Images are NOT uploaded here — Game Center achievement art goes through a
three-step reserve/upload/commit asset flow, and the achievements are valid and
submittable without it. `branding/gamecenter/` holds the 512x512 files for
whoever adds them.

    export ASC_KEY_ID=... ASC_ISSUER_ID=...
    python3 tools/gc_achievements.py            # create what's missing
    python3 tools/gc_achievements.py --dry-run
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import call  # noqa: E402

APP_ID = "6782202277"
LOCALE = "en-US"

# id, referenceName, points, title, beforeEarned, afterEarned, repeatable
ACHIEVEMENTS = [
    ("tidbits.ach.firstgame", "First Tidbit", 10, "First Tidbit",
     "Play your first game.", "You played your first game."),
    ("tidbits.ach.perfect", "Flawless", 25, "Flawless",
     "Finish a round of 7+ questions with 100% accuracy.", "A perfect round — every answer right."),
    ("tidbits.ach.century", "Centurion", 25, "Centurion",
     "Answer 100 questions correctly.", "100 correct answers and counting."),
    ("tidbits.ach.streak7", "On a Roll", 25, "On a Roll",
     "Keep a 7-day daily streak.", "Seven days in a row."),
    ("tidbits.ach.streak30", "Devoted", 50, "Devoted",
     "Keep a 30-day daily streak.", "Thirty days in a row — devoted."),
    ("tidbits.ach.fullpie", "Renaissance", 50, "Renaissance",
     "Earn a knowledge wedge in all seven domains.", "A full pie — mastery across every domain."),
    ("tidbits.ach.sharp", "Sharpshooter", 25, "Sharpshooter",
     "Win a Stake round where every confidence chip lands.", "Perfectly calibrated — every chip landed."),
    ("tidbits.ach.explorer", "Explorer", 25, "Explorer",
     "Play ten different game modes.", "Ten modes explored."),
    ("tidbits.ach.scholar", "Scholar", 50, "Scholar",
     "Answer 1,000 questions correctly.", "1,000 correct — a true scholar."),
]


def detail_id():
    d = call(f"v1/apps/{APP_ID}/gameCenterDetail")
    if "_error" in d:
        sys.exit(f"gameCenterDetail: {d['_detail'][:400]}")
    return d["data"]["id"]


def existing(gc_id):
    d = call(f"v1/gameCenterDetails/{gc_id}/gameCenterAchievements?limit=200")
    return {a["attributes"]["vendorIdentifier"]: a["id"] for a in d.get("data", [])}


def main():
    dry = "--dry-run" in sys.argv
    gc = detail_id()
    have = existing(gc)
    print(f"gameCenterDetail {gc} — {len(have)} achievement(s) already present")

    for vid, ref, points, title, before, after in ACHIEVEMENTS:
        if vid in have:
            print(f"  = {vid:<28} exists")
            continue
        if dry:
            print(f"  + {vid:<28} would create ({points} pts)")
            continue
        r = call("v1/gameCenterAchievements", "POST", {
            "data": {
                "type": "gameCenterAchievements",
                "attributes": {
                    "referenceName": ref,
                    "vendorIdentifier": vid,
                    "points": points,
                    "showBeforeEarned": True,   # all visible — none are hidden
                    "repeatable": False,
                },
                "relationships": {
                    "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gc}},
                },
            }
        })
        if "_error" in r:
            print(f"  ! {vid:<28} create failed: {r['_detail'][:300]}")
            continue
        aid = r["data"]["id"]
        loc = call("v1/gameCenterAchievementLocalizations", "POST", {
            "data": {
                "type": "gameCenterAchievementLocalizations",
                "attributes": {
                    "locale": LOCALE,
                    "name": title,
                    "beforeEarnedDescription": before,
                    "afterEarnedDescription": after,
                },
                "relationships": {
                    "gameCenterAchievement": {"data": {"type": "gameCenterAchievements", "id": aid}},
                },
            }
        })
        ok = "localized" if "_error" not in loc else f"LOCALIZATION FAILED: {loc['_detail'][:200]}"
        print(f"  + {vid:<28} created {aid} ({points} pts) — {ok}")

    total = sum(a[2] for a in ACHIEVEMENTS)
    print(f"total points across the set: {total} (Apple's cap is 1000)")


if __name__ == "__main__":
    main()
