"""Drive the Mac app by PROCESS, never by name.

`tell application "TidbitsTrivia" to activate` looks harmless and is not. It
resolves the NAME, which either launches /Applications/TidbitsTrivia.app
alongside the build under test — two processes with one name, and screenshots of
whichever won the race — or hangs waiting for a launch that never completes,
which killed an entire 18-cell lap. Both were observed. Every call here targets a
specific unix pid instead.

LAUNCHING: through `open`, never by exec'ing the binary. Exec'ing it was the
original design, on the belief that `open` could not forward the TIDBITS_* hooks
a GUI app needs. That belief is now WRONG — `open --env` has existed since macOS
13 — and it cost a whole run: a directly-exec'd bundle is not registered with
LaunchServices, so System Events cannot see it AT ALL ("Can't get process whose
unix id = N. Invalid index"), every capture failed, and the harness reported "no
window ever appeared" about an app that was running fine. Measured on this
machine: exec'd -> System Events cannot resolve the process; `open -n` -> the
windows are there. `ps eww` confirms `--env` reaches the app.
"""
import re
import subprocess
import time
from pathlib import Path

PROC = "TidbitsTrivia"


def _osa(script, timeout=15):
    return subprocess.run(["osascript", "-e", script],
                          capture_output=True, text=True, timeout=timeout)


def quit_all():
    subprocess.run(["pkill", "-x", PROC], capture_output=True)
    time.sleep(1.5)


def launch(app, env=None, timeout=20):
    """Launch the .app through LaunchServices and return its real pid.

    `-n` forces a NEW instance so the build under test is the one measured, and
    `--env` carries the QA hooks that used to require exec'ing the binary.

    The pid comes from pgrep because `open` exits immediately and reports its own
    status, not the app's. Poll rather than sleep a fixed amount: LaunchServices
    needs a moment to tear down the previous instance, and a launch issued into
    that window is silently dropped — which looked exactly like a crash (`pgrep`
    empty, so the caller's AppleScript got an empty pid and failed to parse).
    """
    quit_all()
    import os
    app = str(app)
    if app.endswith("/Contents/MacOS/" + PROC):          # tolerate a binary path
        app = app[: -len("/Contents/MacOS/" + PROC)]
    cmd = ["open", "-n"]
    for k, v in (env or {}).items():
        cmd += ["--env", f"{k}={v}"]
    cmd.append(app)
    subprocess.run(cmd, capture_output=True, timeout=30)

    deadline = time.time() + timeout
    while time.time() < deadline:
        r = subprocess.run(["pgrep", "-f", f"{PROC}.app/Contents/MacOS/{PROC}"],
                           capture_output=True, text=True)
        pids = [int(x) for x in r.stdout.split()]
        if pids:
            return pids[0]
        time.sleep(0.5)
    return None


def close_projectors(pid):
    """Close leftover Tidbits Live projector windows.

    Each hosted night opens one, and macOS restores them all on the next launch —
    a measured session had six stacked up. They are 1280x720 and they sit OVER
    the main window's rectangle, so a screen-region grab of the shell captures a
    projector's idle splash instead."""
    closed = 0
    for i, _name, w, h in reversed(_windows(pid)):
        if _is_projector(w, h):
            try:
                _osa('tell application "System Events" to tell '
                     f'(first process whose unix id is {pid}) to '
                     f'click button 1 of window {i}')
                closed += 1
            except subprocess.SubprocessError:
                pass
    return closed


def raise_pid(pid):
    """Bring this process forward AND raise its MAIN window.

    Raising the process alone is not enough: the frontmost window may be a
    projector, which then covers the shell's rectangle and is what -R captures."""
    try:
        _osa('tell application "System Events" to set frontmost of '
             f'(first process whose unix id is {pid}) to true')
        idx = main_window_index(pid)
        if idx is not None:
            _osa('tell application "System Events" to tell '
                 f'(first process whose unix id is {pid}) to '
                 f'perform action "AXRaise" of window {idx}')
        return True
    except subprocess.SubprocessError:
        return False


# The Tidbits Live PROJECTOR is its own WindowGroup ("tidbits-bigscreen",
# defaultSize 1280x720) and macOS restores it across launches — one measured
# session had SEVEN windows: six restored projectors titled "Tidbits" at
# 1280x720, plus the real main window titled "Records" at 1180x760. Asking for
# "front window" photographed a projector and read its idle splash, "TIDBITS
# LIVE — The host will start the night shortly", as the app ignoring every
# launch hook. The app was correct throughout.
PROJECTOR_SIZE = (1280, 720)


def _is_projector(w, h):
    """Is this window the Tidbits Live big screen rather than the app shell?

    It opens at 1280x720 by default, but on a machine with one display it can
    come up FULL SCREEN — a measured run had it at 2560x1440 as the only window
    the app reported, sitting over the shell. Matching the default size alone
    left it open, so `capture` graded the projector's splash (or, once the shell
    was fully covered, nothing at all) and the run failed with "no window ever
    appeared" while the app was perfectly healthy.

    16:9 and at least 720p is the projector; the shell is not 16:9.
    """
    if (w, h) == PROJECTOR_SIZE:
        return True
    return h >= 720 and abs(w / max(h, 1) - 16 / 9) < 0.02


def _windows(pid):
    """Every window as (index, name, w, h), 1-based to match AppleScript.

    Delimiters are literal characters, not tab/newline escapes: those become
    real whitespace inside the AppleScript source and the parse comes back empty.
    """
    script = (
        'tell application "System Events" to tell '
        f'(first process whose unix id is {pid})\n'
        '  set out to ""\n'
        '  repeat with i from 1 to (count of windows)\n'
        '    set w to window i\n'
        '    set {ww, hh} to size of w\n'
        '    set out to out & (i as text) & "~" & (name of w) & "~" & '
        '(ww as text) & "~" & (hh as text) & "|"\n'
        '  end repeat\n'
        '  return out\n'
        'end tell'
    )
    try:
        r = _osa(script, timeout=25)
    except subprocess.SubprocessError:
        return []
    out = []
    for rec in r.stdout.strip().split("|"):
        f = rec.split("~")
        if len(f) == 4 and f[0].strip().isdigit():
            out.append((int(f[0]), f[1], int(f[2]), int(f[3])))
    return out


def main_window_index(pid):
    """The app's MAIN window: never a projector, and TITLED if there is a choice.

    The app reports two windows — an UNTITLED 1180x708 one and the real shell,
    titled ("Tidbits Live") at 1180x760, the 52px difference being the title bar.
    Taking the first non-projector took the untitled one, so every capture was of
    a window with no traffic lights whose content sat flush at x=0. That is what
    made the sidebar's "Settings & Account" land at x=0.0000 and trip the
    clipped-text check: a harness artifact reported as an app layout bug.

    A titled window is the one a person would call the app's window.
    """
    ws = [(i, n, w, h) for i, n, w, h in _windows(pid) if not _is_projector(w, h)]
    if not ws:
        ws = _windows(pid)          # all projector-sized — fall back rather than guess
    if not ws:
        return None
    for i, name, _w, _h in ws:
        if name.strip():
            return i
    return ws[0][0]


def bounds(pid):
    idx = main_window_index(pid)
    if idx is None:
        return None
    try:
        r = _osa('tell application "System Events" to tell '
                 f'(first process whose unix id is {pid}) to '
                 f'get {{position, size}} of window {idx}', timeout=20)
    except subprocess.SubprocessError:
        return None
    n = [int(x) for x in re.findall(r"-?\d+", r.stdout)]
    return tuple(n[:4]) if len(n) >= 4 else None


def why_no_window(pid):
    """Say WHICH failure this was, so a flaky run is diagnosable from the report.

    "no window ever appeared" covered three different causes — a dead process, an
    app System Events cannot see, and a window too small to grab — and they need
    different fixes.
    """
    if pid is None:
        return ("the app never started — `open` returned but no process appeared. "
                "Usually LaunchServices was still tearing down the previous "
                "instance, or the .app path is wrong")
    # `ps -p` is NOT a liveness check here: a child that exited but was never
    # reaped stays a zombie and ps still finds it, which is how this reported
    # "the process is alive" about an app that was gone. Ask for its state.
    r = subprocess.run(["ps", "-o", "state=", "-p", str(pid)],
                       capture_output=True, text=True)
    state = r.stdout.strip()
    if not state:
        return "the app process exited before a window appeared"
    if state.startswith("Z"):
        return "the app process exited (zombie) before a window appeared"
    ws = _windows(pid)
    if not ws:
        return ("the process is alive but System Events reports NO windows — "
                "usually the app was exec'd directly and never activated, or "
                "Accessibility permission is missing for the terminal")
    sizes = ", ".join(f"{n or '(untitled)'} {w}x{h}" for _, n, w, h in ws)
    return f"windows exist but none was grabbable: {sizes}"


def park_cursor():
    """Move the pointer out of the window before grabbing it.

    Whatever the pointer rests on gets a HOVER TOOLTIP, and the tooltip lands in
    the screenshot. One capture held a help balloon overflowing the right edge
    reading 'Shown as "brought to you by ..." in the' — genuinely severed text,
    but the TOOLTIP's, not the layout's, and the clipping check graded it as an
    app defect. A capture should show the app at rest.

    AppleScript cannot move the mouse (System Events has no such command; the
    obvious-looking "set the position of the mouse" silently does nothing), and
    Quartz/pyobjc is not installed here, so this shells out to a tiny Swift
    snippet using CGWarpMouseCursorPosition. If that is unavailable the capture
    still happens, just without the guarantee.
    """
    src = ('import CoreGraphics\n'
           'CGWarpMouseCursorPosition(CGPoint(x: 4, y: 4))\n')
    try:
        subprocess.run(["swift", "-"], input=src, text=True,
                       capture_output=True, timeout=45)
    except (subprocess.SubprocessError, OSError, FileNotFoundError):
        pass          # worst case a tooltip shows, as before


def ensure_onscreen(pid):
    """Move the window fully on screen before grabbing it.

    `screencapture -R` takes SCREEN coordinates and CLAMPS them to the display, so
    a window sitting at a negative origin is captured cropped: the title bar and
    the left gutter are silently missing from the PNG. That produced an
    intermittent, entirely fake "clipped text" failure — the sidebar's
    "Settings & Account" landed at x=0.0000 in exactly the runs where the window
    had drifted off the left edge, and read as a layout bug in the app.

    macOS restores window position across launches, so whether a run is cropped
    depends on where the window was last left. Pin it instead.
    """
    idx = main_window_index(pid)
    if idx is None:
        return False
    b = bounds(pid)
    if b and b[0] >= 0 and b[1] >= 25:
        return True                      # already clear of the menu bar
    try:
        _osa('tell application "System Events" to tell '
             f'(first process whose unix id is {pid}) to '
             f'set position of window {idx} to {{60, 60}}')
        return True
    except subprocess.SubprocessError:
        return False


def capture(pid, path, tries=12):
    close_projectors(pid)
    """Raise, then grab the window's screen region. -R takes SCREEN pixels, so
    the app must be in front or a terminal gets graded as the app."""
    park_cursor()
    for _ in range(tries):
        raise_pid(pid)
        ensure_onscreen(pid)
        time.sleep(0.7)
        b = bounds(pid)
        if b and b[2] > 200 and b[3] > 200:
            try:
                subprocess.run(["screencapture", "-x", "-o", "-R",
                                f"{b[0]},{b[1]},{b[2]},{b[3]}", str(path)],
                               capture_output=True, timeout=40)
            except subprocess.SubprocessError:
                continue
            if Path(path).exists() and Path(path).stat().st_size > 5000:
                return True
        time.sleep(1.2)
    return False
