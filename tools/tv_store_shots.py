"""Capture Play-store TV screenshots from a real Android TV, verified on the glass.

Play wants 16:9, 1280x720-3840x2160, 24-bit RGB (no alpha; adb screencap emits
RGBA). It gets 1920x1080 straight off the device.

The capture POLLS for each screen's own text signature rather than sleeping a
fixed time. The first version of this slept 9 seconds and produced six files
that were all the HOME screen — the Android TV dongle needs ~18s to draw a
pushed route, and a screenshot taken early is not a screenshot of the surface
you asked for. Every file is OCR-verified before it is written, and the set is
checked for duplicates at the end, because six identical images pass any
per-file check.

    python3 tools/tv_store_shots.py --device androidtv
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import ocr, sh   # noqa: E402

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
DEVICES = {"firetv": "10.0.0.139:5555", "androidtv": "10.0.0.55:5555"}
PKG = "com.tidbitstrivia.app.debug"
ACTIVITY = "com.learningischange.tidbitstrivia.MainActivity"

# (file stem, expected-signature regex, extras)
SHOTS = [
    ("01-home",    r"QUICK PLAY",                        []),
    ("02-game",    r"\d+\s*/\s*\d+",                     [("es", "tidbits_autoplay", "classic:mixed")]),
    ("03-records", r"Your games|Personal bests|No games yet",
                   [("ei", "tidbits_seed_records", "12"), ("es", "tidbits_tab", "records")]),
    ("04-night",   r"Trivia Night|round",                [("ez", "tidbits_night_setup", "true")]),
    ("05-atlas",   r"Knowledge Atlas|map of what you actually know",
                   [("es", "tidbits_open", "atlas")]),
    ("06-picture", r"\d+\s*/\s*\d+",                     [("es", "tidbits_autoplay", "pictureId:mixed")]),
]


def adbs(dev, *args, binary=False, timeout=90):
    serial = DEVICES.get(dev, dev)
    if not re.search(rf"^{re.escape(serial)}\s+device",
                     sh([ADB, "devices"], timeout=30).stdout, re.M):
        sh([ADB, "connect", serial], timeout=30)
    cmd = [ADB, "-s", serial] + list(args)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def capture(dev, path):
    r = adbs(dev, "exec-out", "screencap", "-p", binary=True, timeout=90)
    if not r.stdout:
        return False
    Path(path).write_bytes(r.stdout)
    return True


def text_of(path):
    for d in ocr([(0, Path(path))]).values():
        return " ".join(t["text"] for t in d.get("allText", []))
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="androidtv")
    ap.add_argument("--out", default="docs/store/android-tv")  # committed: the owner needs these
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    from PIL import Image
    results = []
    for stem, sig, extras in SHOTS:
        adbs(a.device, "shell", "am", "force-stop", PKG)
        time.sleep(1)
        args = ["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}",
                "--ez", "tidbits_skip_onboard", "true"]
        for flag, k, v in extras:
            args += [f"--{flag}", k, v]
        adbs(a.device, *args)

        p = out / f"{stem}.png"
        deadline, got = time.time() + 45, ""
        while time.time() < deadline:
            time.sleep(2.5)
            if not capture(a.device, p):
                continue
            got = text_of(p)
            if re.search(sig, got, re.I):
                break
        ok = bool(re.search(sig, got, re.I))
        if not ok:
            print(f"  [MISS] {stem:11s} /{sig}/ never appeared — NOT usable")
            p.unlink(missing_ok=True)
            continue
        im = Image.open(p).convert("RGB")      # Play rejects alpha
        im.save(p)
        w, h = im.size
        ratio_ok = abs(w / h - 16 / 9) < 0.01 and w >= 1280
        print(f"  [ok  ] {stem:11s} {w}x{h} 16:9={ratio_ok}  «{got[:46]}»")
        results.append((stem, got))

    # Six identical files pass every per-file check. Compare them to each other.
    sigs = {}
    dupes = []
    for stem, got in results:
        key = got[:120]
        if key in sigs:
            dupes.append((stem, sigs[key]))
        sigs[key] = stem
    print(f"\n  {len(results)}/{len(SHOTS)} captured, {len(dupes)} duplicate screens")
    for b, a_ in dupes:
        print(f"    DUPLICATE: {b} is the same screen as {a_}")
    return 1 if (dupes or len(results) < len(SHOTS)) else 0


if __name__ == "__main__":
    sys.exit(main())
