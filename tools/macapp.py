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


def raise_pid(pid):
    """Bring exactly this process forward. Never by name."""
    try:
        _osa('tell application "System Events" to set frontmost of '
             f'(first process whose unix id is {pid}) to true')
        return True
    except subprocess.SubprocessError:
        return False


def bounds(pid):
    try:
        r = _osa('tell application "System Events" to tell '
                 f'(first process whose unix id is {pid}) to '
                 'get {position, size} of front window', timeout=20)
    except subprocess.SubprocessError:
        return None
    n = [int(x) for x in re.findall(r"-?\d+", r.stdout)]
    return tuple(n[:4]) if len(n) >= 4 else None


def capture(pid, path, tries=12):
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
