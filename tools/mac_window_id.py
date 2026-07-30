"""Print the CoreGraphics window id of the Tidbits Mac app's main window.

Store screenshots capture the WINDOW (`screencapture -l <id>`), not a screen rectangle —
a rectangle capture put whatever else happened to be on the desktop (in one run, the
Android emulator) into the middle of the frame.
"""
import sys
import Quartz

MIN_WIDTH = 600  # skip tiny panels/tooltips
# The process is TidbitsTrivia but the WINDOW OWNER is the display name, "Tidbits" —
# filtering on the process name found nothing and every frame failed.
OWNERS = {"Tidbits", "TidbitsTrivia"}

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
