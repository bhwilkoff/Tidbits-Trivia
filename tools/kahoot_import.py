#!/usr/bin/env python3
"""Import a Kahoot quiz as a Tidbits Live event file.

    python3 tools/kahoot_import.py <share-url | kahoot-uuid | saved.json> \
        [-o Night.tidbitsevent.json] [--images DIR] [--rehost https://host/path] \
        [--rounds single|by-timer] [--venue "The Anchor"] [--name "Friday Quiz"]

The output is the portable event document in docs/LIVE-EVENT-FILE.md, so it opens
on the Mac (Tidbits Live -> Import event...) and on Windows unchanged. Question
images travel as `imageURL`, which the Mac big screen, the host cockpit and every
joiner (web / iOS / Android) already render.

Where the quiz comes from. A share link's quiz is served anonymously by
`https://create.kahoot.it/rest/kahoots/{uuid}` -- the same JSON the Kahoot
details page loads -- and it carries every choice WITH its `correct` flag, so
nothing has to be scraped off the slides or opened in the editor. A quiz that is
not shared publicly needs a bearer token: pass `--token` (the `token` key in
create.kahoot.it's localStorage) or save the JSON from the browser and pass the
file. The raw JSON is always written next to the output, so a re-import never
needs the network.

Images. Every question image (and the cover) is downloaded into `--images DIR`
(default `<output stem>.images/`) so the host OWNS them; `imageURL` points at
Kahoot's public media CDN by default, which is what the Mac and the phones load
at show time. `--rehost BASE` rewrites `imageURL` to `BASE/<file>` for a host who
serves the folder themselves. Every URL the file references is HEAD-checked and
must answer with an image content type -- a night that looks complete and shows
a broken picture on the projector is the failure this tool exists to prevent.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REST = "https://create.kahoot.it/rest/kahoots/{uuid}"
UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
UA = "TidbitsTrivia-KahootImport/1 (+https://tidbitstrivia.com)"

FORMAT_IDENTIFIER = "com.learningischange.tidbits.live-event"
FORMAT_VERSION = 1

# Kahoot block types that carry a gradable answer, and the GameMode each becomes.
GRADABLE = {
    "quiz": "classic",
    "true_false": "classic",
    "multiple_select_quiz": "classic",
    "jumble": "ordering",
    "open_ended": "typeAnswer",
}
# Blocks with no right answer. They are reported, never silently dropped.
UNGRADABLE = {"survey", "poll", "word_cloud", "brainstorm", "scale", "nps",
              "feedback", "drop_pin", "slider"}
CONTENT = {"content", "slide"}

TAG_RE = re.compile(r"<[^>]+>")


def clean(text):
    """Kahoot stores rich text as HTML fragments; the prompt is plain text."""
    if not text:
        return ""
    t = TAG_RE.sub("", str(text))
    t = (t.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<")
         .replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'"))
    return re.sub(r"\s+", " ", t).strip()


def fetch_json(uuid, token=None):
    req = urllib.request.Request(REST.format(uuid=uuid), headers={"User-Agent": UA,
                                                                    "Accept": "application/json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def head(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except urllib.error.URLError as e:
        return 0, str(e.reason)


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        ctype = r.headers.get("Content-Type", "")
        data = r.read()
    return ctype, data


EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/jpg": ".jpg",
       "image/gif": ".gif", "image/webp": ".webp", "image/svg+xml": ".svg"}


def load_source(src, token):
    p = Path(src)
    if p.exists():
        data = json.loads(p.read_text())
        return data, data.get("uuid", p.stem)
    m = UUID_RE.search(src)
    if not m:
        sys.exit(f"Not a Kahoot share URL, uuid or JSON file: {src}")
    uuid = m.group(0).lower()
    try:
        return fetch_json(uuid, token), uuid
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            sys.exit(f"Kahoot refused the quiz ({e.code}). It is not shared publicly: "
                     "pass --token (localStorage 'token' on create.kahoot.it) or save the "
                     "JSON from the browser and pass the file.")
        sys.exit(f"Kahoot returned HTTP {e.code} for {uuid}")


def question_from(block, index, quiz_uuid, share_url, warnings):
    """Map one gradable Kahoot block to the shared Question shape (LIVE-EVENT-FILE §2.1)."""
    kind = block.get("type", "quiz")
    layout = block.get("layout", "")
    prompt = clean(block.get("question") or block.get("title"))
    n = index + 1
    qid = f"kahoot-{quiz_uuid[:8]}-{n:02d}"
    choices = block.get("choices") or []
    texts = [clean(c.get("answer")) for c in choices]
    for i, c in enumerate(choices):
        if not texts[i] and isinstance(c.get("image"), dict) and c["image"].get("id"):
            warnings.append(f"Q{n}: choice {i + 1} is an IMAGE answer, which Tidbits cannot "
                            "show as a choice; it was labelled 'Picture {}'.".format(chr(65 + i)))
            texts[i] = f"Picture {chr(65 + i)}"
    if not prompt:
        warnings.append(f"Q{n}: no question text; skipped.")
        return None, None

    q = {
        "id": qid,
        "prompt": prompt,
        "options": [],
        "correctIndex": 0,
        "categoryID": "mixed",
        "difficulty": {0: 2, 1: 3, 2: 4}.get(block.get("pointsMultiplier", 1), 3),
        "explanation": "",
        "sourceTitle": "Kahoot",
        "sourceURL": share_url,
        "templateID": "kahoot-" + (kind if kind != "quiz" else layout.lower() or "classic"),
        "tags": ["kahoot"],
    }
    fmt = GRADABLE[kind]

    if fmt == "classic":
        keep = [(t, bool(c.get("correct"))) for t, c in zip(texts, choices) if t]
        if len(keep) < 2:
            warnings.append(f"Q{n}: fewer than two answer choices; skipped.")
            return None, None
        correct = [i for i, (_, ok) in enumerate(keep) if ok]
        if not correct:
            warnings.append(f"Q{n}: no choice is marked correct; skipped.")
            return None, None
        if len(correct) > 1:
            warnings.append(f"Q{n}: {len(correct)} choices are marked correct; Tidbits keeps ONE "
                            f"('{keep[correct[0]][0]}'). Edit it in the builder if that is wrong.")
        lowered = [t.lower() for t, _ in keep]
        if len(set(lowered)) != len(lowered):
            warnings.append(f"Q{n}: two choices are identical text; a player could be right and marked wrong.")
        q["options"] = [t for t, _ in keep]
        q["correctIndex"] = correct[0]
    elif fmt == "ordering":
        items = [t for t in texts if t]
        if len(items) < 3:
            warnings.append(f"Q{n}: a jumble needs at least 3 items; skipped.")
            return None, None
        q["ordering"] = items          # Kahoot stores jumble choices in the CORRECT order
        q["options"] = items
    elif fmt == "typeAnswer":
        accepted = [t for t, c in zip(texts, choices) if t and c.get("correct", True)]
        if not accepted:
            warnings.append(f"Q{n}: open-ended block has no accepted answers; skipped.")
            return None, None
        q["accepted"] = accepted
        q["options"] = [accepted[0]]

    if block.get("pointsMultiplier", 1) != 1:
        warnings.append(f"Q{n}: Kahoot points x{block.get('pointsMultiplier')} has no Tidbits "
                        "equivalent (scoring is per round); difficulty was set instead.")
    video = block.get("video") or {}
    if video.get("fullUrl"):
        warnings.append(f"Q{n}: a YouTube clip ({video['fullUrl']}) does not travel; attach a "
                        "local clip in the builder if the show needs it.")
    return q, fmt


def build_event(kahoot, quiz_uuid, share_url, args, warnings):
    title = clean(kahoot.get("title")) or "Kahoot"
    name = args.name or title
    description = clean(kahoot.get("description"))
    blocks = kahoot.get("questions") or []

    # Pass 1: one (question, format, timerSeconds, image) per gradable block, in order.
    rows = []
    for i, b in enumerate(blocks):
        kind = b.get("type", "quiz")
        n = i + 1
        if kind in CONTENT:
            text = clean(b.get("title") or b.get("description"))
            warnings.append(f"Slide {n} is a content slide ('{text[:60]}'); it is kept as a host "
                            "note on the next round, not as a question.")
            rows.append(("note", text))
            continue
        if kind in UNGRADABLE:
            warnings.append(f"Q{n} is a Kahoot '{kind}' with no correct answer; skipped.")
            continue
        if kind not in GRADABLE:
            warnings.append(f"Q{n} is an unknown Kahoot type '{kind}'; skipped.")
            continue
        q, fmt = question_from(b, i, quiz_uuid, share_url, warnings)
        if q is None:
            continue
        timer = int(round((b.get("time") or 20000) / 1000))
        rows.append(("q", q, fmt, timer, b.get("image") or "", n))

    # Pass 2: rounds. A LiveRound holds ONE format, so a format change always
    # starts a round; a timer change does only under --rounds by-timer, because
    # every round boundary is a standings break on the big screen.
    rounds, current, pending_note = [], None, []
    for row in rows:
        if row[0] == "note":
            pending_note.append(row[1])
            continue
        _, q, fmt, timer, image, n = row
        split = current is None or current["format"] != fmt or \
            (args.rounds == "by-timer" and current["_timer"] != timer)
        if split:
            current = {"id": f"{quiz_uuid[:8]}-round-{len(rounds) + 1}",
                       "title": f"Round {len(rounds) + 1}",
                       "format": fmt, "categoryID": "mixed",
                       "timerSeconds": timer, "_timer": timer, "_timers": [],
                       "hostNote": None, "isWager": False, "isSpeed": False, "isBuzz": False,
                       "questions": [], "_images": []}
            rounds.append(current)
            note = list(pending_note)
            pending_note = []
            if not rounds[:-1] and description:
                note.insert(0, description)
            if note:
                current["hostNote"] = " / ".join(note)
        current["questions"].append(q)
        current["_timers"].append(timer)
        current["_images"].append((q, image, n))
    if pending_note:
        warnings.append("A trailing content slide had no question after it; its text is in the "
                        "last round's host note.")
        if rounds:
            rounds[-1]["hostNote"] = " / ".join(filter(None, [rounds[-1]["hostNote"]] + pending_note))

    for r in rounds:
        # One timer per round: the LONGEST in it, so no question is cut short. The
        # host reveals early whenever the room is done.
        timers = Counter(r["_timers"])
        if len(timers) > 1:
            r["timerSeconds"] = max(timers)
            warnings.append(f"{r['title']}: Kahoot timers vary ({', '.join(f'{k}s x{v}' for k, v in sorted(timers.items()))}); "
                            f"the round uses {r['timerSeconds']}s. Re-run with --rounds by-timer to keep them exact.")
        if len(rounds) == 1:
            r["title"] = args.round_title or title

    event = {
        "id": quiz_uuid,
        "name": name,
        "venue": args.venue or "",
        "createdAt": _iso(kahoot.get("created")),
        "sponsor": "",
        "leadCaptureURL": "",
        "brandHex": "",
        "weekday": None,
        "rounds": rounds,
    }
    return event


def _iso(ms):
    if isinstance(ms, (int, float)) and ms > 0:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def attach_images(event, kahoot, images_dir, rehost, skip_download, warnings):
    """Download every image the night references and verify what the file points at."""
    manifest = []
    jobs = []
    if kahoot.get("cover"):
        jobs.append((None, kahoot["cover"], "cover"))
    for r in event["rounds"]:
        for q, image, n in r["_images"]:
            if image:
                jobs.append((q, image, f"q{n:02d}"))
    if jobs:
        images_dir.mkdir(parents=True, exist_ok=True)
    for q, url, stem in jobs:
        status, ctype = head(url)
        if status != 200 or not ctype.startswith("image/"):
            warnings.append(f"{stem}: {url} answered HTTP {status} {ctype!r}; "
                            "the picture would be BROKEN on the projector, so it was left off.")
            continue
        fname = stem + EXT.get(ctype.split(";")[0].strip(), ".img")
        dest = images_dir / fname
        if not skip_download:
            ctype2, data = download(url, dest)
            dest.write_bytes(data)
        manifest.append({"file": fname, "source": url, "question": q["id"] if q else "cover"})
        if q is not None:
            q["imageURL"] = f"{rehost.rstrip('/')}/{fname}" if rehost else url
    if rehost:
        for m in manifest:
            if m["question"] != "cover":
                status, ctype = head(f"{rehost.rstrip('/')}/{m['file']}")
                if status != 200 or not ctype.startswith("image/"):
                    warnings.append(f"{m['file']}: {rehost} does not serve it yet (HTTP {status}); "
                                    "upload the images folder before the night.")
    for r in event["rounds"]:
        for key in ("_images", "_timer", "_timers"):
            r.pop(key, None)
    return manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("source", help="Kahoot share URL, quiz uuid, or a saved Kahoot JSON file")
    ap.add_argument("-o", "--output", help="the .tidbitsevent.json to write (default: <title>.tidbitsevent.json)")
    ap.add_argument("--images", help="folder for the downloaded images (default: <output stem>.images/)")
    ap.add_argument("--rehost", help="serve the images folder yourself: rewrite imageURL to BASE/<file>")
    ap.add_argument("--rounds", choices=["single", "by-timer"], default="single",
                    help="single: one round per format (default); by-timer: also split when Kahoot's timer changes")
    ap.add_argument("--name", help="event name (default: the Kahoot title)")
    ap.add_argument("--round-title", help="title of the round when the quiz becomes one round (default: the Kahoot title)")
    ap.add_argument("--venue", help="venue line for the big screen")
    ap.add_argument("--token", help="Kahoot bearer token for a quiz that is not shared publicly")
    ap.add_argument("--no-download", action="store_true", help="verify the image URLs but do not save copies")
    args = ap.parse_args()

    warnings = []
    kahoot, quiz_uuid = load_source(args.source, args.token)
    share_url = args.source if args.source.startswith("http") else f"https://create.kahoot.it/details/{quiz_uuid}"
    title = clean(kahoot.get("title")) or "Kahoot"
    safe = re.sub(r"[/\\:]", "-", args.name or title).strip() or "Kahoot"
    out = Path(args.output) if args.output else Path(f"{safe}.tidbitsevent.json")
    stem = out.name.replace(".tidbitsevent.json", "").replace(".json", "")
    images_dir = Path(args.images) if args.images else out.with_name(stem + ".images")

    event = build_event(kahoot, quiz_uuid, share_url, args, warnings)
    manifest = attach_images(event, kahoot, images_dir, args.rehost, args.no_download, warnings)

    doc = {
        "format": FORMAT_IDENTIFIER,
        "version": FORMAT_VERSION,
        "exportedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "app": "tools/kahoot_import.py",
        "droppedClipCount": 0,
        "event": event,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    raw = out.with_name(stem + ".kahoot.json")
    raw.write_text(json.dumps(kahoot, indent=2, ensure_ascii=False) + "\n")
    if manifest:
        (images_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    total = sum(len(r["questions"]) for r in event["rounds"])
    pictured = sum(1 for r in event["rounds"] for q in r["questions"] if q.get("imageURL"))
    print(f"{out}")
    print(f"  {title!r}: {len(kahoot.get('questions') or [])} Kahoot blocks -> "
          f"{total} questions in {len(event['rounds'])} round(s), {pictured} with pictures")
    for r in event["rounds"]:
        print(f"  - {r['title']}: {len(r['questions'])} x {r['format']}, {r['timerSeconds']}s")
    if manifest:
        print(f"  images: {images_dir}/ ({len(manifest)} files, incl. cover)")
    print(f"  raw Kahoot JSON: {raw}")
    if warnings:
        print(f"  {len(warnings)} note(s):")
        for w in warnings:
            print(f"    ! {w}")
    if total == 0:
        sys.exit("No gradable questions came across.")


if __name__ == "__main__":
    main()
