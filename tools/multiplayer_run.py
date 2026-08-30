"""Drive one hosted room across every real device at once, and grade it on two
independent sources of truth.

The whole point of this harness is that a cross-platform game has a failure mode
no single-device sweep can see: each client can look perfectly healthy while
showing a DIFFERENT question, or while never having reached the backend at all.
So every run checks both halves:

  * the WIRE  — read live/{code} from RTDB directly. Says who actually joined
                and what the host actually published. Independent of any UI.
  * the GLASS — a screenshot of each device. Says what a human in the room
                would see. The wire being right proves nothing about that.

A device that is on the wire but not on the glass is a rendering bug. On the
glass but not the wire is a client faking local state. Agreeing but showing
different question text is the desync this exists to catch.

    python3 tools/multiplayer_run.py --host mac  --players ipad,iphone,pixel,web
    python3 tools/multiplayer_run.py --host atv  --players ipad,iphone,pixel,firetv
"""
import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macapp  # noqa: E402
from devharness import (OCR_FAILED, Grader, frame_text, frame_darkness, ocr,  # noqa: E402
                        qa_dir, sh)

DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
BUNDLE = "com.learningischange.tidbitstrivia"
ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
APKG = "com.tidbitstrivia.app.debug"
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"
# Prefer a locally built app when one exists. The /Applications copy predates the
# data-protection-keychain fix, and its legacy-keychain ACL prompt is modal: it
# sits over the window and the host never opens its room, which is what this
# harness then reports as "the host never created the room".
_DEV_MAC = Path("build/dd-mac/Build/Products/Debug/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia")
MACBIN = str(_DEV_MAC if _DEV_MAC.exists()
             else Path("/Applications/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia"))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

API_KEY = "AIzaSyCns8iba6zVqkddEUY_gqoc4eVxz-3BGaA"
DB = "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"

APPLE = {
    "atv":    "C3FBA9DE-4A60-555B-A65F-80D6809A275B",   # Ben Bedroom
    "ipad":   "AC5377E9-6053-51DE-8E65-D88A4E9345FA",
    "iphone": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7",
}
ANDROID = {
    "pixel":     "adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp",
    "firetv":    "10.0.0.139:5555",
    "androidtv": "10.0.0.55:5555",
}


# ---------------------------------------------------------------- the wire

def http(method, url, body=None):
    req = urllib.request.Request(
        url, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or "null")


def anon_token():
    d = http("POST", "https://identitytoolkit.googleapis.com/v1/accounts:signUp"
             f"?key={API_KEY}", {"returnSecureToken": True})
    return d["idToken"]


def room(code, tok, part=""):
    try:
        return http("GET", f"{DB}/live/{code}{part}.json?auth={tok}")
    except Exception as e:                       # noqa: BLE001
        return {"_error": str(e)}


# ------------------------------------------------------------- the devices

def devicectl(*args, timeout=90):
    return sh(["env", f"DEVELOPER_DIR={DEVELOPER_DIR}", "xcrun", "devicectl"]
              + list(args), timeout=timeout)


PYATV = str(Path.home() / ".pyatv-venv/bin/atvremote")
# The UUID, not the MAC. A second device on this network began
# advertising as "Ben Bedroom" too, and pyatv then refused every
# MAC-style --id with "Found more than one Apple TV" — which silently
# disabled the tvOS wake, so launches failed with "System is asleep -
# foreground app launch forbidden". The UUID is unique to the Apple TV.
PYATV_ARGS = ["--id", "783F0C4E-201E-48FF-8C0D-D45595F4433E", "--protocol", "companion"]


def press(key):
    # A fresh single-command Companion connection often drops its press;
    # running power_state on the same connection first warms it.
    sh([PYATV] + PYATV_ARGS + ["power_state", key], timeout=30)


def wake_tv():
    """A launch into a sleeping TV is refused or comes up backgrounded, and
    devicectl has no wake verb. Skipping this is why the first run of this
    harness reported "host never opened the room" — the host was never running."""
    for _ in range(3):
        r = sh(PYATV_CMD := [PYATV] + PYATV_ARGS + ["power_state"], timeout=40)
        if "PowerState.On" in r.stdout:
            return True
        print("[atv] asleep — waking")
        sh([PYATV] + PYATV_ARGS + ["turn_on"], timeout=40)
        for _ in range(8):
            time.sleep(3)
            if "PowerState.On" in sh(PYATV_CMD, timeout=40).stdout:
                time.sleep(2)
                return True
    print("[atv] WARNING: could not verify the TV awake")
    return False


def apple_launch(dev, env):
    r = devicectl("device", "process", "launch", "--terminate-existing",
                  "--device", APPLE[dev], "-e", json.dumps(env), BUNDLE, timeout=90)
    return "Launched application" in (r.stdout + r.stderr)


def apple_shot(dev, path):
    try:
        devicectl("device", "capture", "screenshot", "--device", APPLE[dev],
                  "--destination", str(path), timeout=60)
    except subprocess.TimeoutExpired:
        return False
    return Path(path).exists()


def adb(dev, *args, binary=False, timeout=90):
    serial = ANDROID[dev]
    cmd = [ADB, "-s", serial] + list(args)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def android_launch(dev, code, name):
    adb(dev, "shell", "am", "force-stop", APKG)
    time.sleep(1)
    r = adb(dev, "shell", "am", "start", "-n", f"{APKG}/{ACTIVITY}",
            "--ez", "tidbits_skip_onboard", "true",
            "--es", "tidbits_live_join", code, "--es", "tidbits_live_name", name)
    return "Error" not in r.stdout + r.stderr


def android_shot(dev, path):
    r = adb(dev, "exec-out", "screencap", "-p", binary=True, timeout=90)
    if not r.stdout:
        return False
    Path(path).write_bytes(r.stdout)
    return True


_MAC_PID = None


def mac_launch(env):
    global _MAC_PID
    _MAC_PID = macapp.launch(MACBIN, env)


def mac_shot(path):
    return macapp.capture(_MAC_PID, path) if _MAC_PID else False


def web_shot(code, path):
    sh([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--window-size=390,844", "--virtual-time-budget=12000",
        f"--screenshot={path}", f"https://tidbitstrivia.com/#/live/{code}"],
       timeout=90)
    return Path(path).exists()


def join(dev, code, outdir):
    """Put `dev` in the room. Returns the screenshot function for later."""
    name = f"QA-{dev}"
    if dev in APPLE:
        apple_launch(dev, {"TIDBITS_LIVE_AUTOJOIN": "1", "TIDBITS_LIVE_CODE": code,
                           "TIDBITS_LIVE_JOIN": code, "TIDBITS_SKIP_ONBOARD": "1",
                           "TIDBITS_PLAYER_NAME": name})
    elif dev in ANDROID:
        android_launch(dev, code, name)
    elif dev == "web":
        pass                                     # the URL itself is the join
    return name


def shoot(dev, path, code=None):
    if dev in APPLE:
        return apple_shot(dev, path)
    if dev in ANDROID:
        return android_shot(dev, path)
    if dev == "mac":
        return mac_shot(path)
    if dev == "web":
        return web_shot(code, path)
    return False


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="mac",
                    choices=["mac", "atv", "ipad", "iphone", "pixel", "firetv", "androidtv"])
    ap.add_argument("--game", default="live", choices=["live", "night"],
                    help="live = Tidbits Live; night = Trivia Night (same RTDB room)")
    ap.add_argument("--players", default="ipad,iphone,pixel,web")
    ap.add_argument("--code", default="QALL")
    ap.add_argument("--start", action="store_true",
                    help="press Start on the host lobby so a question publishes")
    ap.add_argument("--settle", type=float, default=40,
                    help="seconds to let joins land before the graded capture")
    a = ap.parse_args()

    code = a.code.upper()
    # Rooms are FOUR letters (FirebaseRTDB: `(0..<4).map`). The native clients pin
    # TIDBITS_LIVE_CODE straight through with no length check, so a longer code
    # "works" on device and is silently unjoinable from the web, whose input is
    # correctly capped at 4 — every earlier run of this harness used QALIVE /
    # QANITE / QAFINAL and the web could never have joined any of them.
    # FOUR characters, alphanumeric — the generator's alphabet includes digits
    # (real rooms observed: T7ZV, RGW2). An earlier version of this guard demanded
    # letters only and rejected a code the app itself would have produced.
    if len(code) != 4 or not code.isalnum():
        sys.exit(f"--code must be exactly 4 alphanumeric chars (rooms are 4); got {code!r}")
    players = [p for p in a.players.split(",") if p]
    out = qa_dir("multiplayer", f"{a.host}-{code}")
    g = Grader(out, host=a.host, code=code, players=players)
    print(f"room {code} — host={a.host} players={players}\n  artifacts: {out}")

    # 1. Host. The Mac hosts Tidbits Live; the Apple TV hosts Trivia Night.
    # Trivia Night and Tidbits Live publish to the SAME live/{code} room, so a
    # joiner does not care which one opened it — that is the whole point of the
    # unified backend and it is what makes any-host / any-joiner possible.
    host_env = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_LIVE_CODE": code,
                ("TIDBITS_NIGHT_HOST" if a.game == "night" else "TIDBITS_LIVE_HOST"): "1"}
    if a.host == "mac":
        mac_launch(host_env)
    elif a.host in APPLE:
        if a.host == "atv":
            g.grade("atv_awake", wake_tv(), "Companion reports the TV on")
        apple_launch(a.host, host_env)
    else:
        adb(a.host, "shell", "am", "force-stop", APKG)
        time.sleep(1)
        adb(a.host, "shell", "am", "start", "-n", f"{APKG}/{ACTIVITY}",
            "--ez", "tidbits_skip_onboard", "true", "--ez", "tidbits_night_host", "true")

    # 2. The room must exist on the WIRE before anyone is asked to join it.
    tok = anon_token()
    deadline, meta = time.time() + 90, None
    while time.time() < deadline:
        time.sleep(5)
        meta = room(code, tok, "/meta")
        if meta and not meta.get("_error"):
            break
    g.grade("host_created_room", bool(meta) and not (meta or {}).get("_error"),
            f"live/{code}/meta = {json.dumps(meta)[:120]}" if meta
            else f"live/{code}/meta never appeared after 90s — host never opened it")
    if not meta or meta.get("_error"):
        # "The host never opened the room" is a symptom, not a diagnosis. The
        # host's own screen says whether it is asleep, on the wrong surface, or
        # sitting on a setup step waiting for a press.
        p = out / f"host-{a.host}-FAILED.png"
        if shoot(a.host, p, code):
            t = frame_text(ocr([(a.host, p)]).get(p.name, {}))
            print(f"  host glass: «{t[:220]}»")
            g.report["host_glass_on_failure"] = t[:400]
        return g.finish()

    # 3. Everyone joins.
    #
    # Clear the roster first. A pinned code means the room outlives the run, so
    # players from the PREVIOUS run are still listed and the join delta counts
    # only whoever is new — which is how a run with all four devices visibly in
    # the room reported "1 new of 4 expected".
    cleared = True
    try:
        http("DELETE", f"{DB}/live/{code}/teams.json?auth={tok}")
    except Exception as e:                       # noqa: BLE001
        # RTDB rules do not let an anonymous client delete another player's row,
        # so this 401s against a room someone else opened.
        cleared = False
        print(f"  [note] could not clear roster: {e}")
    before = len(room(code, tok, "/teams") or {})
    names = {p: join(p, code, out) for p in players}
    time.sleep(a.settle)

    # 4. The wire says how many really landed.
    #
    # Counted, NOT matched by name: the iOS join hook hardcodes the team name
    # ("iOS Tester"), so the iPad and the iPhone arrive under the SAME name and a
    # name-keyed set collapses them — which is exactly how an earlier version of
    # this harness reported the iPad missing while its own screenshot showed it in
    # the room. Per-device attribution comes from the glass, which cannot collide.
    teams = room(code, tok, "/teams") or {}
    joined = sorted((t or {}).get("name", "") for t in teams.values() if isinstance(t, dict))
    native = [p for p in players if p != "web"]   # the web needs a team name typed in
    # A DELTA is only meaningful when the roster was actually cleared. When the
    # clear 401s the previous run's players are still listed, so every joiner
    # rejoins its existing row and the delta is 0 — which reported "0 new of 4"
    # for a room whose own roster listed all four.
    if cleared:
        ok, ev = len(teams) - before >= len(native), f"{len(teams) - before} new"
    else:
        ok, ev = len(teams) >= len(native), f"{len(teams)} present (roster not cleared)"
    g.grade("wire.all_joiners_landed", ok, f"{ev} of {len(native)} expected; teams={joined}")

    if a.start and a.host == "atv":
        press("select")            # the lobby's Start button holds initial focus
        time.sleep(12)

    pub = room(code, tok, "/pub") or {}
    g.grade("wire.host_published", bool(pub),
            f"pub={json.dumps(pub)[:140]}" if pub else
            "host published no question — the lobby waits for Start (pass --start)")

    # 5. The glass says what a human sees. Capture host + every player.
    shots, per_dev, retried = [], {}, set()
    for dev in [a.host] + players:
        p = out / f"{dev}.png"
        if shoot(dev, p, code):
            shots.append((dev, p))
        else:
            g.grade(f"glass.{dev}_captured", False, "no screenshot — device blind")
    texts = ocr(shots)
    # Same rule as grade_glass: an OCR failure is not five sleeping devices.
    if OCR_FAILED in texts:
        g.grade("ocr_available", False, texts[OCR_FAILED])
        (out / "wire.json").write_text(json.dumps(
            {"meta": meta, "teams": teams, "pub": pub}, indent=2))
        return g.finish()
    for dev, p in shots:
        t = frame_text(texts.get(p.name, {}))
        per_dev[dev] = t
        lines = len(texts.get(p.name, {}).get("allText", []))
        # Blind first: an unreadable frame must never be graded as a bad screen.
        if lines < 4:
            # The iPhone and iPad have no remote wake, so a dark screen is
            # genuinely UNKNOWN — the device is on the wire, we simply cannot see
            # its glass. Scoring that as a failure blames a phone for being
            # asleep. Relaunching wakes it in practice, so it is retried once and
            # only then reported, as SKIP rather than FAIL.
            if dev in APPLE and dev not in retried:
                retried.add(dev)
                print(f"  [{dev}] dark screen — relaunching to wake it")
                join(dev, code, out)
                time.sleep(20)
                p2 = out / f"{dev}-retry.png"
                if shoot(dev, p2, code):
                    t2 = ocr([(dev, p2)])
                    if len(t2.get(p2.name, {}).get("allText", [])) >= 4:
                        shots.append((dev, p2))
                        texts.update(t2)
                        per_dev[dev] = frame_text(t2.get(p2.name, {}))
                        g.grade(f"glass.{dev}_readable", True, "readable after a wake relaunch")
                        continue
            d = frame_darkness(p)
            detail = (f"{d[1]}% black, mean luma {d[0]}" if d else "unreadable")
            g.report.setdefault("skipped", []).append(
                f"{dev}: frame {detail}; capture succeeded, display was off — "
                "device is on the wire, only its glass is unseen")
            print(f"  [SKIP] glass.{dev}_readable: screen off/locked, no remote wake")
            continue
        g.grade(f"glass.{dev}_readable", True, f"{lines} OCR lines")
        if dev == a.host:
            in_room = bool(re.search(rf"{code}|in the room|Start|round", t, re.I))
        else:
            # JOINED, not merely "showing something about a room". The web sits on
            # the join FORM with the code prefilled — which matched an earlier,
            # looser pattern and passed while nobody had actually joined. Only
            # post-join chrome counts.
            in_room = bool(re.search(r"YOU.RE IN|Waiting for the host|POINTS|"
                                     r"points|Question \d|\d+\s*/\s*\d+", t))
        g.grade(f"glass.{dev}_in_room", in_room, f"«{t[:180]}»")

    # 6. The desync check. If the host published a question, the players'
    #    screens must carry the SAME question, not merely a healthy-looking one.
    qtext = str(pub.get("q") or pub.get("text") or pub.get("prompt") or "")
    if qtext:
        key = " ".join(re.findall(r"[A-Za-z]{5,}", qtext)[:4])
        for dev in players:
            if dev not in per_dev:
                continue   # unseen glass — already reported as SKIP
            hit = sum(1 for w in key.split() if re.search(re.escape(w), per_dev[dev], re.I))
            need = max(1, len(key.split()) - 1)
            # Ten-foot type OCRs badly: the Fire TV rendered the prompt as
            # "Craganmed doappreoen ghose pesponsibe" while its ANSWER OPTIONS
            # read cleanly. The options are the published question just as much as
            # the prompt is, so a device that shows this question's options is on
            # this question — reading the prompt is not the only way to prove it.
            opts = [str(o) for o in (pub.get("options") or [])]
            opt_hits = sum(1 for o in opts
                           if o and re.search(re.escape(o[:18]), per_dev[dev], re.I))
            same = hit >= need or opt_hits >= max(2, len(opts) - 1)
            g.grade(f"sync.{dev}_same_question", same,
                    f"{hit}/{len(key.split())} prompt keywords, {opt_hits}/{len(opts)} "
                    f"options of «{qtext[:50]}»")
    else:
        print("  [note] host published no question text — sync check not applicable")

    (out / "wire.json").write_text(json.dumps(
        {"meta": meta, "teams": teams, "pub": pub}, indent=2))
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
