"""Drive the Mac app by PROCESS, never by name.

`tell application "TidbitsTrivia" to activate` looks harmless and is not. The
harnesses exec the app binary directly (that is the only way TIDBITS_* env hooks
reach a GUI app), so the running instance is not a LaunchServices-registered
application. AppleScript therefore resolves the NAME instead, which either

  * launches /Applications/TidbitsTrivia.app alongside the build under test —
    two processes with one name, and screenshots of whichever won the race, or
  * hangs indefinitely waiting for a launch that never completes, which killed
    an entire 18-cell lap when the timeout propagated.

Both were observed. Every call here targets a specific unix pid, so the app under
test is the app measured, and a name collision cannot occur.
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


def launch(binary, env=None):
    """Exec the binary directly and return its real pid. Popen with a list (not
    a shell string) is what makes the pid the APP's rather than a shell's."""
    quit_all()
    import os
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.Popen([str(binary)], env=e,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return p.pid


def close_projectors(pid):
    """Close leftover Tidbits Live projector windows.

    Each hosted night opens one, and macOS restores them all on the next launch —
    a measured session had six stacked up. They are 1280x720 and they sit OVER
    the main window's rectangle, so a screen-region grab of the shell captures a
    projector's idle splash instead."""
    closed = 0
    for i, _name, w, h in reversed(_windows(pid)):
        if (w, h) == PROJECTOR_SIZE:
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
    """The app's MAIN window, never a projector. Projectors are identified by
    their fixed 1280x720 default; anything else is the shell."""
    ws = _windows(pid)
    if not ws:
        return None
    for i, name, w, h in ws:
        if (w, h) != PROJECTOR_SIZE:
            return i
    return ws[0][0]      # all projector-sized — fall back rather than guess


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


def capture(pid, path, tries=12):
    close_projectors(pid)
    """Raise, then grab the window's screen region. -R takes SCREEN pixels, so
    the app must be in front or a terminal gets graded as the app."""
    for _ in range(tries):
        raise_pid(pid)
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
