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
import devlease  # noqa: E402
import devreset  # noqa: E402
import macapp  # noqa: E402
import winbox  # noqa: E402
import webdrive  # noqa: E402
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
_SHIPPED_MAC = Path("/Applications/TidbitsTrivia.app/Contents/MacOS/TidbitsTrivia")
MACBIN = str(_DEV_MAC if _DEV_MAC.exists() else _SHIPPED_MAC)


def mac_binary_is_current():
    """Refuse to run a Mac build older than the keychain fix.

    The fallback above is only correct while `build/dd-mac` EXISTS. It did not, so
    every Mac launch quietly used the /Applications copy — dated 2026-08-25, five
    days older than the data-protection-keychain fix — and the owner got a login
    keychain password prompt on his own machine, twice, from a defect that had
    already been fixed and proven.

    A stale binary is the worst kind of wrong: it fails as the ORIGINAL bug, so the
    obvious reading is that the fix regressed. Checking the mtime against the fix's
    own source file costs nothing and makes the fallback say when it is unsafe.
    """
    src = Path("TidbitsTrivia/Core/Networking/Keychain.swift")
    binp = Path(MACBIN)
    if not binp.exists():
        return False, f"{MACBIN} does not exist — build it with -derivedDataPath build/dd-mac"
    if src.exists() and binp.stat().st_mtime < src.stat().st_mtime:
        return False, (f"{MACBIN} predates {src} — it will raise the legacy-keychain "
                       "password prompt that was already fixed. Rebuild: xcodebuild "
                       "build -scheme TidbitsTrivia -destination 'platform=macOS' "
                       "-derivedDataPath build/dd-mac")
    return True, MACBIN
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


def apple_launch(dev, env, retries=1):
    """Launch, and VERIFY it launched.

    "Launched application" in the output is devicectl reporting that it sent the
    request, not that the app is running. Straight after a reset the two race: the
    terminate is still tearing the process down when the launch arrives, the launch
    reports success, and the device sits on its Home Screen. That is exactly what an
    iPad did in a six-device run — it was the only one missing from the room, and the
    harness had nothing to say beyond "the expected words were not on screen".
    """
    for attempt in range(retries + 1):
        r = devicectl("device", "process", "launch", "--terminate-existing",
                      "--device", APPLE[dev], "-e", json.dumps(env), BUNDLE, timeout=90)
        if "Launched application" not in (r.stdout + r.stderr):
            time.sleep(3)
            continue
        time.sleep(4)
        info = devicectl("device", "info", "processes", "--device", APPLE[dev], timeout=90)
        # Match the EXECUTABLE PATH, not the bundle id. `devicectl device info
        # processes` lists paths like
        #   /private/var/containers/Bundle/Application/<uuid>/TidbitsTrivia.app/TidbitsTrivia
        # and the bundle id appears zero times in it. Searching for the bundle id
        # therefore reported "not running" for every Apple device on every launch —
        # and the retry it triggered relaunched with --terminate-existing, killing a
        # host that was already up and resetting its autostart clock. A verifier that
        # cannot pass is worse than no verifier: this one actively broke the runs it
        # was added to stabilise.
        if "TidbitsTrivia.app/TidbitsTrivia" in (info.stdout or ""):
            return True
        if attempt < retries:
            print(f"  [{dev}] launch reported success but no process — retrying")
            time.sleep(3)
    print(f"  [{dev}] the app is NOT running after {retries + 1} launch attempts")
    return False


def apple_shot(dev, path):
    # Wake the TV before EVERY capture, not just before a join. This box sleeps
    # between steps on its own: a run woke it to join, it joined, and by capture time
    # it was asleep again — reported as "device blind" on a device that was in the
    # room the whole time. Cheap when it is already awake (a power_state query).
    if dev == "atv":
        wake_tv()
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
            "--es", "tidbits_live_join", code, "--es", "tidbits_live_name", name,
            "--es", "tidbits_qa_label", f"join {code} {name}")
    return "Error" not in r.stdout + r.stderr


def android_top(dev):
    """Which package is actually in FRONT. Returns "" when it cannot be read.

    A capture is only evidence about this app if this app is the one on screen. The
    Fire TV joined a room correctly on the wire and its screenshot was a film
    catalogue — some other app had come forward — and all the harness could say was
    that the expected words were missing, which reads like a Tidbits bug. Naming the
    top package turns "wrong text" into "the top app is com.amazon.tv.launcher".
    """
    r = adb(dev, "shell", "dumpsys", "window", "|", "grep", "-E", "mCurrentFocus")
    out = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"([A-Za-z0-9_.]+)/[A-Za-z0-9_.]+", out)
    return m.group(1) if m else ""


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


# One browser for the whole run, opened at join time and photographed later — the
# session has to survive between the two or the join is thrown away.
_WEB = None


def web_join(code, team="QA-web"):
    """Actually JOIN, rather than just load the page.

    `#/live/CODE` lands on the join FORM with the code filled and the name empty:
    correct behaviour (you name yourself), and unreachable by `--screenshot`. Every
    previous run of this harness loaded that URL, photographed the form, and graded
    the web as "not in the room" — which was true, and was the harness's doing.

    Driven the way a person does it: type into the field, dispatch the input event
    React-style so the app's state actually updates, press Join. Not via a new
    auto-join URL parameter — that would be changing the product to make a test
    pass, and would ship a "join as any name" link for the harness's convenience.
    """
    global _WEB
    try:
        _WEB = webdrive.Browser()
        _WEB.goto(f"https://tidbitstrivia.com/#/live/{code}", settle=6)
        r = _WEB.js("""(() => {
          const t = document.querySelector('#live-team');
          const j = document.querySelector('#live-join');
          if (!t || !j) return 'no-form';
          const set = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value').set;
          set.call(t, %r);
          t.dispatchEvent(new Event('input', {bubbles: true}));
          j.click();
          return 'joined';
        })()""" % team)
        return r == "joined", r
    except Exception as e:                            # noqa: BLE001
        return False, str(e)[:200]


def web_shot(code, path):
    """Photograph the SAME browser that joined. A fresh headless Chrome would be a
    different session with none of the join state, which is the trap the old
    implementation fell into."""
    if _WEB is None:
        return False
    try:
        return _WEB.screenshot(path)
    except Exception:                                 # noqa: BLE001
        return False


def join(dev, code, outdir):
    """Put `dev` in the room. Returns the screenshot function for later."""
    name = f"QA-{dev}"
    if dev == "atv":
        # Wake it FIRST. A launch into a sleeping Apple TV is refused outright —
        # devicectl returns "System is asleep - foreground app launch forbidden" — and
        # the harness only ever woke the TV when it was the HOST. As a joiner it was
        # asked to launch into a sleeping box in every run, reported honestly as "the
        # app is NOT running", and read like a tvOS defect.
        wake_tv()

    if dev == "windows":
        # Windows could HOST and could not JOIN through this harness: `join()` had
        # branches for mac, APPLE, ANDROID and web, and Windows fell straight through.
        # The app has had TIDBITS_LIVE_JOIN since the hook-coverage pass; nothing here
        # ever used it, so the Windows box was listed as a player in every night run
        # and its screenshot was the bare desktop.
        winbox.launch({"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_LIVE_JOIN": code,
                       "TIDBITS_LIVE_NAME": name,
                       "TIDBITS_QA_LABEL": f"join {code} {name}"}, wait=16)
    elif dev == "mac":
        # The Mac could HOST from the very first version of this harness and could
        # never JOIN: `join()` had branches for APPLE, ANDROID and web, and the Mac
        # silently fell through, returning a name without launching anything. It was
        # listed as a player in every run and asked to do nothing, then reported as
        # "device blind" when its screenshot showed the Home screen.
        mac_launch({"TIDBITS_LIVE_AUTOJOIN": "1", "TIDBITS_LIVE_CODE": code,
                    "TIDBITS_LIVE_JOIN": code, "TIDBITS_SKIP_ONBOARD": "1",
                    "TIDBITS_LIVE_NAME": name,
                    "TIDBITS_QA_LABEL": f"join {code} {name}"})
    elif dev in APPLE:
        # TIDBITS_LIVE_NAME, not TIDBITS_PLAYER_NAME: the latter was never read by
        # anything. Every Apple device joined as its hard-coded default, so the iPhone
        # and the iPad both showed up as "iOS Tester" — two rows with one name, and a
        # join count that reported "3 of 4 landed" while all four were in the room.
        apple_launch(dev, {"TIDBITS_LIVE_AUTOJOIN": "1", "TIDBITS_LIVE_CODE": code,
                           "TIDBITS_LIVE_JOIN": code, "TIDBITS_SKIP_ONBOARD": "1",
                           "TIDBITS_LIVE_NAME": name,
                           "TIDBITS_QA_LABEL": f"join {code} {name}"})
    elif dev in ANDROID:
        android_launch(dev, code, name)
    elif dev == "web":
        ok, why = web_join(code, name)
        if not ok:
            print(f"  [note] web join failed: {why}")
    return name


def win_shot(path):
    """The Windows box's real display. Its own module because a Windows capture is
    a scheduled task in the interactive session, not a command over ssh — from ssh
    (session 0) it photographs a phantom desktop nobody is looking at."""
    ok, _ = winbox.screenshot(path, remote_name="mp-shot.png")
    return ok


def shoot(dev, path, code=None):
    if dev == "windows":
        return win_shot(path)
    if dev in APPLE:
        return apple_shot(dev, path)
    if dev in ANDROID:
        top = android_top(dev)
        if top and not top.startswith("com.tidbitstrivia"):
            # Another app is in front. On this bench that is usually the TV's own
            # launcher or a media app waking up — the Fire TV joined a room correctly
            # on the wire while com.archivewatch.app sat on the glass.
            #
            # Bring Tidbits forward ONCE and say so. Recovering silently would hide a
            # real background-crash, which looks identical from the outside; recovering
            # loudly keeps the run useful without pretending nothing happened.
            print(f"  [{dev}] foreground was {top}, not Tidbits — rejoining {code}")
            # `am start` with the SAME join intent, not `monkey -c LAUNCHER`. A bare
            # launcher intent starts the app with no extras, so it opens on Home rather
            # than in the room — and on the Fire TV it did not even come forward, which
            # is why the first version of this reported "the app will not stay in
            # front" when what had happened was that it was never asked to rejoin.
            if code:
                android_launch(dev, code, f"QA-{dev}")
                # POLL for the room, do not guess a duration. A fixed 8s caught the
                # Android TV on Tidbits' own Home screen — the app had come forward and
                # the join had not landed yet — which then graded as "not in the room"
                # and pointed at the wrong thing entirely.
                for _ in range(10):
                    time.sleep(3)
                    if android_top(dev).startswith("com.tidbitstrivia"):
                        names = [(v or {}).get("name") for v in
                                 (room(code, anon_token(), "/teams") or {}).values()]
                        if f"QA-{dev}" in names:
                            break
            again = android_top(dev)
            if again and not again.startswith("com.tidbitstrivia"):
                print(f"  [{dev}] STILL {again} — the app will not stay in front")
        return android_shot(dev, path)
    if dev == "atv":
        # Wake it FIRST. A launch into a sleeping Apple TV is refused outright —
        # devicectl returns "System is asleep - foreground app launch forbidden" — and
        # the harness only ever woke the TV when it was the HOST. As a joiner it was
        # asked to launch into a sleeping box in every run, reported honestly as "the
        # app is NOT running", and read like a tvOS defect.
        wake_tv()

    if dev == "windows":
        # Windows could HOST and could not JOIN through this harness: `join()` had
        # branches for mac, APPLE, ANDROID and web, and Windows fell straight through.
        # The app has had TIDBITS_LIVE_JOIN since the hook-coverage pass; nothing here
        # ever used it, so the Windows box was listed as a player in every night run
        # and its screenshot was the bare desktop.
        winbox.launch({"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_LIVE_JOIN": code,
                       "TIDBITS_LIVE_NAME": name,
                       "TIDBITS_QA_LABEL": f"join {code} {name}"}, wait=16)
    elif dev == "mac":
        return mac_shot(path)
    if dev == "web":
        return web_shot(code, path)
    return False


def code_on_screen(text, tok):
    """The 4-char room code the host is actually showing, confirmed against RTDB.

    Every host surface prints its code big — it has to, since that is how people
    join. Candidates are checked against the backend before being believed: an OCR
    of a trivia screen is full of 4-character words, and following the wrong one
    would produce a confident run against a room nobody is in.
    """
    seen = set()
    for w in re.findall(r"\b[A-Z0-9]{4}\b", (text or "").upper()):
        if w in seen:
            continue
        seen.add(w)
        m = room(w, tok, "/meta")
        if m and not m.get("_error"):
            return w
    return None


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="mac",
                    choices=["mac", "atv", "windows",
                             "ipad", "iphone", "pixel", "firetv", "androidtv"])
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

    # 0a. LEASE every device first. Another agent session was driving these same TVs
    # from a different repo: each of us kept finding the other's app in front, each
    # force-stopped the other's app as part of its own reset, and each diagnosed it as
    # a bug in its own product. A contended device is SKIPPED and reported, never
    # stolen — a run that honestly did not cover a device beats one that reports a
    # tug-of-war as a Tidbits failure.
    wanted = sorted(set(players + [a.host]))
    held = []
    for d in wanted:
        ok, holder = devlease.try_lease(d, task=f"{a.game} {code} (host={a.host})")
        if ok:
            held.append(d)
        else:
            print(f"  [skip] {d} is leased by {holder}")
            g.grade(f"lease.{d}", False, f"not covered this run — leased by {holder}")
    if a.host not in held:
        g.grade("host_leased", False, f"cannot run: the host {a.host} is in use elsewhere")
        return g.finish()
    players = [p for p in players if p in held]

    try:
        return _run_room(a, code, players, out, g, held)
    finally:
        for d in held:
            devlease.release(d)


def _run_room(a, code, players, out, g, held):
    import time                                   # noqa: F811  (kept local + explicit)

    # 0b. Put every device BACK. Nothing used to, so a run launched on top of whatever
    # the last one left — a device still in the previous room would show up on the wire
    # and be counted as having joined THIS one.
    print("  resetting the bench")
    devreset.reset_all(players + [a.host])
    time.sleep(2)

    # 1. Host. The Mac hosts Tidbits Live; the Apple TV hosts Trivia Night.
    # Trivia Night and Tidbits Live publish to the SAME live/{code} room, so a
    # joiner does not care which one opened it — that is the whole point of the
    # unified backend and it is what makes any-host / any-joiner possible.
    host_env = {"TIDBITS_SKIP_ONBOARD": "1", "TIDBITS_LIVE_CODE": code,
                "TIDBITS_QA_LABEL": f"HOST {a.game} {code}",
                # A night waits in a lobby for a human. The grace must land INSIDE the
                # settle window: long enough for joiners to arrive, early enough that
                # the question has published before the wire is read. The first version
                # used settle+10 and fired ten seconds after the check that was looking
                # for it, so every Apple host reported "published no question" while
                # about to publish one.
                **({"TIDBITS_NIGHT_AUTOSTART": str(max(5, int(a.settle) - 20))}
                   if a.game == "night" else {}),
                ("TIDBITS_NIGHT_HOST" if a.game == "night" else "TIDBITS_LIVE_HOST"): "1"}
    # A stale Mac binary re-raises a fixed bug and reads as a regression, so say so
    # before the run rather than after the prompt is on the owner's screen.
    if a.host == "mac" or "mac" in players:
        cur, why = mac_binary_is_current()
        if not cur:
            g.grade("mac_binary_current", False, why)
            players = [p for p in players if p != "mac"]
            if a.host == "mac":
                return g.finish()

    if a.host == "windows":
        # TIDBITS_LIVE_HOST takes a PRESET NAME on Windows, not a flag: every route
        # into StartHosting is a Click handler, so the hook picks which night to
        # host rather than merely asking for one. "1" is not a preset, and the hook
        # deliberately falls back to the first one rather than silently doing
        # nothing — a harness that asked for a host must never grade the setup screen.
        winbox.launch(dict(host_env, TIDBITS_LIVE_HOST="Quick Night",
                           TIDBITS_TAB="live"), wait=16)
    elif a.host == "mac":
        mac_launch(host_env)
    elif a.host in APPLE:
        if a.host == "atv":
            g.grade("atv_awake", wake_tv(), "Companion reports the TV on")
        apple_launch(a.host, host_env)
    else:
        adb(a.host, "shell", "am", "force-stop", APKG)
        time.sleep(1)
        adb(a.host, "shell", "am", "start", "-n", f"{APKG}/{ACTIVITY}",
            "--ez", "tidbits_skip_onboard", "true", "--ez", "tidbits_night_host", "true",
            "--es", "tidbits_qa_label", f"HOST {a.game} {code}",
            *(["--ei", "tidbits_night_autostart", str(max(5, int(a.settle) - 20))]
              if a.game == "night" else []))

    # 2. The room must exist on the WIRE before anyone is asked to join it.
    #
    # The code may not be the one we asked for. Android's night host GENERATES its
    # own — the Pixel opened a perfectly good lobby showing "SCAN TO JOIN XLT6" while
    # this harness watched live/NX01 and reported "the host never opened it". So when
    # the pinned code does not appear, READ the code off the host's own screen, which
    # is exactly what a real host does before telling anyone. That also removes a
    # per-platform hook the product does not need to grow.
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
        # "The host never opened the room" is a symptom, not a diagnosis. The host's
        # own screen says whether it is asleep, on the wrong surface, sitting on a
        # setup step waiting for a press — or hosting under a code of its own.
        p = out / f"host-{a.host}-FAILED.png"
        t = ""
        if shoot(a.host, p, code):
            t = frame_text(ocr([(a.host, p)]).get(p.name, {}))
            print(f"  host glass: «{t[:220]}»")
            g.report["host_glass_on_failure"] = t[:400]

        found = code_on_screen(t, tok)
        if found:
            print(f"  host is hosting {found}, not {code} — following its code")
            g.grade("host_code_read_from_screen", True,
                    f"asked for {code}; the host opened {found} and it is live")
            code = found
            meta = room(code, tok, "/meta")
        else:
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
    # Keep the Windows box awake THROUGH the settle. It locks fast, and a run that
    # spends 50s waiting for joins then photographs a lock screen wastes the whole
    # run — the capture is correctly refused, so the host's own glass goes ungraded.
    settle_end = time.time() + a.settle
    while time.time() < settle_end:
        time.sleep(min(20, max(1, settle_end - time.time())))
        if a.host == "windows" or "windows" in players:
            winbox.keep_awake()
        for d in held:
            devlease.renew(d)          # a long run must not expire mid-flight

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

    # POLL for the first question rather than reading once.
    #
    # A night's autostart clock begins when the ROOM opens, and the joins run after
    # that — eight devices take their own time — so a single read straight after the
    # settle can land in the gap before the first publish. It did: the iPad was graded
    # "published no question" and its screenshot, taken moments later in the same run,
    # showed ROUND 1/3 Q1/5 with all seven joiners in the standings. The wire and the
    # glass disagreed because the wire was read too early, not because they differed.
    pub = {}
    deadline = time.time() + 60
    while time.time() < deadline:
        pub = room(code, tok, "/pub") or {}
        if pub:
            break
        time.sleep(5)
    g.grade("wire.host_published", bool(pub),
            f"pub={json.dumps(pub)[:140]}" if pub else
            "host published no question in 60s after the settle — the lobby is still "
            "waiting for Start, and TIDBITS_NIGHT_AUTOSTART did not fire")

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
        # A TV that has drifted back to its own launcher is READABLE and not in the
        # room, so the dark-screen recovery above never fired for it: the Apple TV was
        # graded against "Community Favorites / prime video fubo plutotv". Both TVs do
        # this on their own — the Fire TV already gets a rejoin on the Android path,
        # and this is its Apple twin. Rejoin once, recapture, and say that it needed it.
        if not in_room and dev != a.host and dev not in retried:
            retried.add(dev)
            print(f"  [{dev}] readable but not in the room — rejoining {code}")
            join(dev, code, out)
            time.sleep(18)
            p3 = out / f"{dev}-rejoin.png"
            if shoot(dev, p3, code):
                t3 = ocr([(dev, p3)])
                nt = frame_text(t3.get(p3.name, {}))
                if re.search(r"YOU.RE IN|Waiting for the host|POINTS|points|"
                             r"Question \d|\d+\s*/\s*\d+", nt):
                    in_room, t = True, nt
                    per_dev[dev] = nt
                    texts.update(t3)
                    g.report.setdefault("rejoined", []).append(dev)

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


def _shutdown():
    global _WEB
    if _WEB is not None:
        _WEB.close()
        _WEB = None


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        _shutdown()
