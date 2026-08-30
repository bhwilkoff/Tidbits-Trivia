"""Shared spine for the real-hardware harnesses (tvOS / iOS / Android).

Archive Watch runs three hand-written harnesses that share nothing but an OCR
binary, and it pays for that: its iOS harness has no wake, no alive probe and no
retry ladder because the tvOS resilience was never back-ported. Everything here
is the part that is genuinely platform-agnostic — OCR, grading, artifact paths,
and the blind-instrument guard — so a lesson learned on one device reaches all
of them.

Device plumbing deliberately does NOT live here. Waking a tvOS box over
Companion, unlocking a Pixel over adb, and giving up on a locked iPad are not
the same operation wearing different hats, and pretending otherwise is how you
get a lowest-common-denominator harness that cannot express what any one
platform actually needs.
"""
import json
import re
import subprocess
import time
from pathlib import Path

OCR = "/tmp/tbocr"

# A frame carrying fewer than this many OCR lines is unreadable — a locked or
# sleeping device yields zero, a real app screen yields many. Line count is
# resolution independent, which a byte-size threshold is not.
MIN_LINES_READABLE = 4

# Text at the very frame edge is text the layout could not fit. Thresholds are
# CALIBRATED per platform against a real capture, never copied: Archive Watch's
# 0.010 called three correctly-rendered Tidbits headings clipped on every frame,
# because our own gutter sits at x=0.0099-0.0116 on the iPad.
CLIP_X_DEFAULT = 0.005

FORBID_DEFAULT = (r"No questions|Couldn.t load|Something went wrong|"
                  r"failed to|\berror\b|couldn.t be")


def sh(cmd, timeout=90, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


def qa_dir(platform, name):
    """build/qa/<platform>-<date>/<name>-<epoch>/ — durable, never /tmp, because
    background tasks get reaped and a capture you cannot return to is a capture
    you have to take twice."""
    d = (Path("build/qa") / f"{platform}-{time.strftime('%Y-%m-%d')}"
         / f"{name}-{int(time.time())}")
    d.mkdir(parents=True, exist_ok=True)
    return d


# Set by ocr() when the OCR process itself failed. Callers MUST check it before
# reading a low line count as "the screen was dark".
OCR_FAILED = "__ocr_failed__"


def ocr(shots):
    """OCR a list of (wall, Path). Batched 20 per process to amortize launch.

    A failed OCR process used to be indistinguishable from a dark screen: the
    result dict simply came back empty and every frame graded as "0 OCR lines —
    SCREEN OFF/LOCKED". Measured on a loaded machine, a five-device multiplayer
    run reported all five devices asleep while their screenshots were on disk and
    perfectly readable a minute later. An instrument that blames its subject for
    its own failure is worse than one that stays quiet, so a chunk that yields
    nothing for files that DO exist is recorded as an instrument failure."""
    out = {}
    paths = [str(p) for _, p in shots]
    for chunk in (paths[k:k + 20] for k in range(0, len(paths), 20)):
        try:
            r = sh([OCR] + chunk, timeout=600)
        except (OSError, subprocess.SubprocessError) as e:
            # OCR lives in /tmp, so it does not survive a reboot. A traceback
            # here is better than a false "screen off", but a sentence saying
            # how to get it back is better than either.
            out[OCR_FAILED] = (f"cannot run {OCR}: {e} — rebuild with "
                               f"`swiftc -O tools/ScreenOCR/main.swift -o {OCR}`")
            return out
        got = 0
        for line in r.stdout.splitlines():
            try:
                d = json.loads(line)
                out[d["file"]] = d
                got += 1
            except json.JSONDecodeError:
                pass
        present = [c for c in chunk if Path(c).exists()]
        if present and got == 0:
            out[OCR_FAILED] = (f"{OCR} produced nothing for {len(present)} existing "
                               f"file(s), rc={r.returncode}: "
                               f"{(r.stderr or r.stdout).strip()[:160]!r}")
    return out


def frame_text(d):
    return " ".join(t["text"] for t in d.get("allText", []))


def clipped_lines(d, clip_x=CLIP_X_DEFAULT):
    """Lines starting at the frame gutter. Big display type is excluded by
    height: a hero numeral legitimately spans the frame, chrome type never
    starts at the edge."""
    return [t for t in d.get("allText", [])
            if t.get("x", 1.0) <= clip_x and t.get("h", 1.0) <= 0.030]


class Grader:
    """Collects assertions, prints them as they are decided, and writes a
    machine-comparable report.json. Archive Watch's Android and iOS harnesses
    print and exit with no JSON, so nothing there can be compared across runs
    and there is no regression baseline at all — this exists so ours can be."""

    def __init__(self, outdir, **meta):
        self.outdir = Path(outdir)
        self.report = dict(meta)
        self.report["assertions"] = {}
        self.failures = []

    def grade(self, key, ok, evidence):
        self.report["assertions"][key] = {"pass": bool(ok), "evidence": evidence}
        print(f"  [{'PASS' if ok else 'FAIL'}] {key}: {evidence}")
        if not ok:
            self.failures.append(key)
        return bool(ok)

    def grade_glass(self, shots, texts, spec, anchor_rx, clip_x=CLIP_X_DEFAULT):
        """The standard glass battery, in the order that keeps it honest.

        The blind check comes FIRST and gates everything downstream: a null
        result from a blind instrument is indistinguishable from a real absence,
        so an unreadable run must be skipped, never passed."""
        # The instrument speaks first. "The screen was dark" is a claim about the
        # DEVICE, and it must not be made when the OCR process is what failed.
        if OCR_FAILED in texts:
            self.grade("ocr_available", False, texts[OCR_FAILED])
            return False
        counts = [len(texts.get(p.name, {}).get("allText", [])) for _, p in shots]
        best = max(counts, default=0)
        readable = best >= MIN_LINES_READABLE
        self.grade("screen_awake", readable, f"best frame had {best} OCR lines"
                   + ("" if readable else " — SCREEN OFF/LOCKED, nothing was graded"))
        if not readable:
            return False

        all_text = " | ".join(frame_text(texts.get(p.name, {})) for _, p in shots)

        # A READABLE frame of the WRONG app survives every other check and then
        # answers questions about a screen we are not testing.
        owns = bool(re.search(anchor_rx, all_text, re.I))
        self.grade("app_owns_glass", owns, "Tidbits chrome on the glass" if owns
                   else "readable frames, but no Tidbits chrome — wrong app/screen")

        if "expect_any" in spec:
            m = re.search(spec["expect_any"], all_text, re.I)
            self.grade("expect_any", bool(m), f"/{spec['expect_any']}/ "
                       + (f"matched {m.group(0)!r}" if m else "matched nothing"))

        bad = re.search(spec.get("forbid", FORBID_DEFAULT), all_text, re.I)
        self.grade("no_error_text", not bad,
                   "clean" if not bad else f"found {bad.group(0)!r}")

        clipped = {p.name: [t["text"] for t in clipped_lines(texts.get(p.name, {}), clip_x)]
                   for _, p in shots}
        clipped = {k: v for k, v in clipped.items() if v}
        self.grade("no_clipped_text", not clipped, "no edge clipping"
                   if not clipped else f"clipped: {clipped}")
        return True

    def finish(self):
        ok = not self.failures
        self.report["result"] = "OK" if ok else "FAIL"
        (self.outdir / "report.json").write_text(json.dumps(self.report, indent=2))
        print(f"\nRESULT: {'OK' if ok else 'FAIL — ' + ', '.join(self.failures)}")
        print(f"report: {self.outdir}/report.json")
        return 0 if ok else 1
