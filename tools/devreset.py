"""Return every device to a known, empty state — and SAY what it is about to test.

Two problems, one cause. Nothing in this harness ever put a device BACK: a run
left the app wherever it finished — mid-round, still in a room, hosting a night —
and the next run launched on top of that. So a test could inherit the previous
test's screen, and looking at a device on the desk told you nothing about what was
being tested on it.

    reset("pixel")                     # stop the app, leave the device idle
    reset_all(["ipad", "pixel"])       # in parallel where the tool allows
    label("pixel", "daily · empty state")   # what this device is for, on its screen

`label` sets TIDBITS_QA_LABEL, which every client renders as a small banner. It is
inert when unset, so it costs a shipped build nothing — and it means a photograph
of the bench is self-describing, instead of six screens that all look like Tidbits.
"""
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

DEVELOPER_DIR = "/Applications/Xcode-beta.app/Contents/Developer"
BUNDLE = "com.learningischange.tidbitstrivia"
ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
APKG = "com.tidbitstrivia.app.debug"

APPLE = {
    "atv":    "C3FBA9DE-4A60-555B-A65F-80D6809A275B",
    "ipad":   "AC5377E9-6053-51DE-8E65-D88A4E9345FA",
    "iphone": "B4E756E2-CBFA-5F63-8CEE-21D226637AF7",
}
ANDROID = {
    "pixel":     "adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp",
    "firetv":    "10.0.0.139:5555",
    "androidtv": "10.0.0.55:5555",
}


def _run(cmd, timeout=60, env=None):
    e = dict(os.environ, **(env or {}))
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=e)
        return r.returncode == 0, (r.stdout + r.stderr).strip()
    except (subprocess.SubprocessError, OSError) as ex:
        return False, str(ex)[:200]


def reset(dev):
    """Stop the app on `dev`. Returns (ok, detail).

    Deliberately a STOP, not a data wipe. `adb pm clear` would also erase records,
    the daily streak and the sign-in — state a test may legitimately need, and
    state that belongs to the owner on their own devices. What causes a stale
    screen is a running process, not saved data.
    """
    if dev in APPLE:
        # terminate, not "launch --terminate-existing": a reset must be able to
        # leave a device with NOTHING running, or "reset then look" just shows the
        # app again and proves nothing.
        return _run(["xcrun", "devicectl", "device", "process", "terminate",
                     "--device", APPLE[dev], "--bundle-identifier", BUNDLE],
                    env={"DEVELOPER_DIR": DEVELOPER_DIR})
    if dev in ANDROID:
        return _run([ADB, "-s", ANDROID[dev], "shell", "am", "force-stop", APKG])
    if dev == "mac":
        return _run(["pkill", "-x", "TidbitsTrivia"])
    if dev == "windows":
        import winbox
        winbox.quit_app()
        return True, "stopped"
    if dev == "web":
        return _run(["pkill", "-f", "tidbits-cdp-profile"])
    return False, f"unknown device {dev!r}"


def reset_all(devs, verbose=True):
    out = {}
    for d in devs:
        ok, detail = reset(d)
        out[d] = ok
        if verbose:
            # A failed reset is reported, never swallowed: the next test would then
            # be grading the previous test's screen and would look like it passed.
            print(f"  reset {d:10} {'ok' if ok else 'FAILED — ' + detail[:70]}")
    return out


def label_env(text):
    """The env/extras a client needs to draw the banner."""
    return {"TIDBITS_QA_LABEL": text}
