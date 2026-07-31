"""Print the CoreGraphics window id of the Tidbits Mac app's main window.

Store screenshots capture the WINDOW (`screencapture -l <id>`), not a screen rectangle —
a rectangle capture put whatever else happened to be on the desktop (in one run, the
Android emulator) into the middle of the frame.
"""
import subprocess
import sys

try:
    import Quartz
except ImportError:                     # pyobjc is not installed on every machine
    Quartz = None

# AppleScript fallback: window BOUNDS, for `screencapture -R`. Still the app's window only —
# never a full-screen grab. A full-screen capture during a QA run swept the developer's
# terminal and an emulator into the frame, which is exactly what this file exists to avoid.
BOUNDS_SCRIPT = '''
tell application "System Events"
  tell process "Tidbits"
    if (count of windows) = 0 then return ""
    set p to position of window 1
    set s to size of window 1
    return (item 1 of p as text) & "," & (item 2 of p as text) & "," & \
           (item 1 of s as text) & "," & (item 2 of s as text)
  end tell
end tell
'''


def bounds_fallback():
    """x,y,w,h of the app window, or "" — usable as `screencapture -R<x,y,w,h>`."""
    out = subprocess.run(["osascript", "-e", BOUNDS_SCRIPT],
                         capture_output=True, text=True).stdout.strip()
    return out

MIN_WIDTH = 600  # skip tiny panels/tooltips
# The process is TidbitsTrivia but the WINDOW OWNER is the display name, "Tidbits" —
# filtering on the process name found nothing and every frame failed.
OWNERS = {"Tidbits", "TidbitsTrivia"}

if Quartz is None:
    b = bounds_fallback()
    print(f"RECT:{b}" if b else "", end="" if not b else "\n")
    sys.exit(0 if b else 1)

def main() -> int:
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    ) or []
    best, best_area = None, 0
    for w in windows:
        if w.get("kCGWindowOwnerName") not in OWNERS:
            continue
        b = w.get(Quartz.kCGWindowBounds) or {}
        width, height = b.get("Width", 0), b.get("Height", 0)
        if width < MIN_WIDTH:
            continue
        if width * height > best_area:
            best, best_area = int(w["kCGWindowNumber"]), width * height
    if best is None:
        return 1
    print(best)
    return 0

if __name__ == "__main__":
    sys.exit(main())
