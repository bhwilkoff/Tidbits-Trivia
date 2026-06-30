#!/usr/bin/env python3
"""Push Tidbits' Google Play "App content" + store listing via the Play Developer API — the parts that
DON'T need the Console. Submits the Data Safety declaration (tools/play-data-safety.csv) and the en-US
store listing (title, descriptions, phone screenshots from branding/play-screenshots/). The build/upload
of the AAB is separate — see tools/submit-play.sh.

  PLAY_SERVICE_ACCOUNT_JSON=~/.config/play/archivewatch-play.json tools/push-play-content.py
        [--listing-only | --data-safety-only]

Console-only (no API exists): content rating (IARC), target audience, privacy policy URL, ads
declaration, app access. See docs/CLOUD-SUBMISSION.md.

Keep TITLE/SHORT/FULL in sync with docs/play-store-listing.md. Screenshots in branding/play-screenshots/
are pre-padded to <=2:1 (Play's phone-screenshot max aspect ratio); the iPhone-native 1206x2622 shots in
branding/screenshots/ are 2.17:1 and Play rejects them.
"""
import os, glob, sys, argparse
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

PKG = os.environ.get("PLAY_PACKAGE", "com.tidbitstrivia.app")
KEY = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", os.path.expanduser("~/.config/play/tidbits-play.json"))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "tools", "play-data-safety.csv")
SHOTS = os.path.join(ROOT, "branding", "play-screenshots")
FEATURE = os.path.join(ROOT, "branding", "play-feature-graphic.png")  # 1024x500, no alpha

TITLE = "Tidbits: Wikipedia Trivia"
SHORT = "Real trivia from all of Wikipedia. Play the daily, learn a fact, keep a streak."
FULL = """Tidbits turns the whole of Wikipedia into a trivia game - and unlike most quiz apps, every question is built from real, sourced facts, with a "learn the fact" card after each one so you walk away knowing something new.

WHY TIDBITS IS DIFFERENT
- Real facts, not recycled questions. Over 11,000 questions, generated and fact-checked from Wikipedia and Wikidata - and they never repeat until you've seen them all.
- 22 kinds of questions. Identify a subject from a clue, fill in the blank, put events in order, find the odd one out, pick the biggest or the earliest, and more. The variety keeps you thinking, not pattern-matching.
- Learn as you play. Every question ends with the fact and a link to read more. Miss one? It quietly comes back later, so the game teaches as it tests.

WAYS TO PLAY
- Daily Tidbit - the same seven questions for everyone, every day. Build a streak.
- Classic, Time Attack, and Survival modes.
- Eight categories: History, Science, Geography, Arts & Lit, Film & TV, Music, Sports, and a Mixed Bag.
- Create a quiz from ANY topic - type "jazz" or "volcanoes" or your hometown and Tidbits builds a quiz from Wikipedia on the spot.

BUILT TO RESPECT YOU
- Works fully offline - the question bank lives on your device.
- No ads. No energy meters. No "pay to keep your streak." No dark patterns.
- Free. The goal is to make you a little more curious, not to farm your attention.

Tidbits is also on the web, iPhone, iPad, and Apple TV - same game everywhere."""


def svc():
    if not os.path.isfile(KEY):
        raise SystemExit(f"Service-account JSON not found: {KEY} (set PLAY_SERVICE_ACCOUNT_JSON)")
    creds = service_account.Credentials.from_service_account_file(
        KEY, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def push_data_safety(s):
    print("=== Data Safety ===")
    s.applications().dataSafety(packageName=PKG,
                                body={"safetyLabels": open(CSV, encoding="utf-8").read()}).execute()
    print("OK — declaration accepted (no data collected, no data shared)")


def push_listing(s):
    print("=== Store listing (en-US) ===")
    assert len(TITLE) <= 30 and len(SHORT) <= 80 and len(FULL) <= 4000
    eid = s.edits().insert(body={}, packageName=PKG).execute()["id"]
    s.edits().listings().update(packageName=PKG, editId=eid, language="en-US",
                                body={"language": "en-US", "title": TITLE,
                                      "shortDescription": SHORT, "fullDescription": FULL}).execute()
    for itype, paths in (("phoneScreenshots", sorted(glob.glob(os.path.join(SHOTS, "*.png")))),
                         ("featureGraphic", [FEATURE] if os.path.isfile(FEATURE) else [])):
        s.edits().images().deleteall(packageName=PKG, editId=eid, language="en-US",
                                     imageType=itype).execute()
        for p in paths:
            s.edits().images().upload(packageName=PKG, editId=eid, language="en-US",
                                      imageType=itype,
                                      media_body=MediaFileUpload(p, mimetype="image/png")).execute()
    shots = sorted(glob.glob(os.path.join(SHOTS, "*.png")))
    s.edits().validate(packageName=PKG, editId=eid).execute()
    s.edits().commit(packageName=PKG, editId=eid).execute()
    print(f"OK — title + descriptions + {len(shots)} screenshots + feature graphic committed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listing-only", action="store_true")
    ap.add_argument("--data-safety-only", action="store_true")
    a = ap.parse_args()
    s = svc()
    try:
        if not a.listing_only:
            push_data_safety(s)
        if not a.data_safety_only:
            push_listing(s)
    except HttpError as e:
        body = e.content.decode() if hasattr(e.content, "decode") else str(e)
        raise SystemExit(f"Play API error {getattr(e,'status_code','')}: {body}")


if __name__ == "__main__":
    main()
