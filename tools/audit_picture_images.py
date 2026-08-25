#!/usr/bin/env python3
"""Liveness audit for every picture-round image URL in assets/picture.json.

The testers' "images not loading" class at corpus scale: a Commons file that
was renamed or deleted 404s through Special:FilePath, and the player sees the
failure text. Check all 5,721 BEFORE a player does. Wikimedia requires a real
User-Agent; concurrency kept polite.

Usage: python3 tools/audit_picture_images.py [--limit N] [--out report.json]
Exit 1 if any URL is dead.
"""
import concurrent.futures as cf
import json, sys, time, urllib.request, urllib.error

UA = "TidbitsTrivia-QA/1.0 (https://tidbitstrivia.com; contact via site)"
OUT = next((a.split("=",1)[1] for a in sys.argv if a.startswith("--out=")),
           "build/qa/picture-image-audit.json")
LIMIT = next((int(a.split("=",1)[1]) for a in sys.argv if a.startswith("--limit=")), None)


def check(row):
    qid, url = row[0], row[9]
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return (qid, url, r.status, r.headers.get("Content-Type", ""))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503) and attempt == 1:
                time.sleep(20)
                continue
            return (qid, url, e.code, "")
        except Exception as e:
            if attempt == 1:
                time.sleep(3)
                continue
            return (qid, url, -1, str(e)[:80])


def main():
    qs = json.load(open("assets/picture.json"))["questions"]
    if LIMIT:
        qs = qs[:LIMIT]
    print(f"[audit] {len(qs)} picture URLs")
    bad, unknown, done = [], [], 0
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=3) as ex:
        for res in ex.map(check, qs):
            done += 1
            qid, url, status, extra = res
            # A live image is 200 image/*; HTML back means a Commons error page.
            if status == 429 or status in (500, 502, 503, -1):
                # Transient failures NEVER mark (the marker rule): a throttled
                # check is a blind instrument, not a dead image. The first run
                # of this audit called 3,333 rate-limited rows "dead".
                unknown.append({"id": qid, "url": url, "status": status})
            elif status != 200 or not extra.startswith("image/"):
                bad.append({"id": qid, "url": url, "status": status, "info": extra})
                print(f"[DEAD] {status} {qid} {url[:90]}", flush=True)
            if done % 500 == 0:
                print(f"[audit] {done}/{len(qs)} ({time.time()-t0:.0f}s), {len(bad)} dead")
    json.dump({"checked": len(qs), "dead": bad, "unverified": len(unknown),
               "unknown": unknown[:50]}, open(OUT, "w"), indent=1)
    print(f"\n{len(bad)} dead, {len(unknown)} UNVERIFIED (throttled/transient) of {len(qs)} -> {OUT}")
    # Unverified is not clean: exit 2 so a gate cannot read throttled as green.
    sys.exit(1 if bad else (2 if unknown else 0))


if __name__ == "__main__":
    main()
