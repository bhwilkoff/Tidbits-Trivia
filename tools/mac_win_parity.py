"""Measure Mac -> Windows parity by the USER-VISIBLE VOCABULARY of each app.

The parity tracker is a hand-maintained checklist, and a hand-maintained
checklist drifts: four Tidbits items were carried as missing for weeks while the
code already had them (see the documented-backlog-sweep memory). So this does not
read the tracker. It reads the two codebases and asks a question neither can
answer about itself: which words does the Mac say to a person that Windows never
says?

Vocabulary rather than a feature list, because a feature list is exactly the
hand-maintained artifact that drifts. A string a person can READ is evidence the
surface exists; its absence on the other platform is a LEAD, not a verdict --
platforms legitimately word things differently, and every hit still has to be
confirmed by looking.
"""
import re, sys, pathlib, json, collections

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAC  = [ROOT / "TidbitsTrivia/macOS", ROOT / "TidbitsTrivia/Core"]
WIN  = [ROOT / "windows/Tidbits.App", ROOT / "windows/Tidbits.Core"]

# SwiftUI/XAML idiom, symbol names, and format plumbing are not things a person
# reads. Left in, they drown the signal: "systemImage" outnumbers real copy.
NOISE = re.compile(
    r"^(?:[a-z]+\.[a-z0-9.]+|%[@dsf]|#[0-9A-Fa-f]{3,8}|[\d\s.,:/+%-]*|"
    r"[a-z]+(?:[A-Z][a-z]*)+|\w+\.(?:png|jpg|json|sqlite|db)|"
    r"(?:http|file)s?:.*|[A-Z_]{2,}(?:_[A-Z]+)*)$")
UI_ATTR = re.compile(r'(?:Text|Content|Header|Title|Watermark|ToolTip\.Tip|'
                     r'Description|PlaceholderText)\s*=\s*"([^"{}]{3,60})"')

def words(s):
    return {w for w in re.findall(r"[A-Za-z][A-Za-z'-]{2,}", s.lower())}

# bin/ and obj/ carry the BUNDLED CORPUS (~33k trivia questions as JSON). Left
# in, every word any question happens to use counts as "Windows says this", so a
# genuinely missing surface reads as present -- the instrument reports parity it
# has not measured. Excluding build output is what makes the result mean anything.
SKIP = {"bin", "obj", "artifacts", "publish", ".git"}

def harvest(dirs, exts, extra=None):
    out = collections.Counter()
    for d in dirs:
        for p in d.rglob("*"):
            if p.suffix not in exts or not p.is_file():
                continue
            if SKIP & set(p.relative_to(d).parts):
                continue
            txt = p.read_text(errors="ignore")
            found = re.findall(r'"([^"\\\n]{3,60})"', txt)
            if extra:
                found += extra.findall(txt)
            for s in found:
                s = s.strip()
                # Real copy has a space or is a short Title-case label.
                if NOISE.match(s):
                    continue
                if " " not in s and not re.match(r"^[A-Z][a-z]{2,}$|^[A-Z ]{3,}$", s):
                    continue
                out[s] += 1
    return out

mac = harvest(MAC, {".swift"})
win = harvest(WIN, {".cs", ".axaml"}, extra=UI_ATTR)

win_vocab = set()
for s in win:
    win_vocab |= words(s)

# A Mac phrase is a LEAD when the distinctive words in it appear nowhere in the
# whole Windows vocabulary -- not when the exact phrase differs. "Play previous
# days" vs "Past dailies" is a wording difference; a phrase whose every content
# word is absent from Windows means the CONCEPT is absent.
STOP = words("the a an and or of to for in on with your you it is are be this that "
             "no not now new all more from at as by can will get set")
leads = []
for s, n in mac.items():
    w = words(s) - STOP
    if not w:
        continue
    missing = w - win_vocab
    if len(missing) == len(w):          # nothing in this phrase is known to Windows
        leads.append((len(w), s, sorted(missing)[:4]))

leads.sort(key=lambda t: -t[0])
print(f"Mac phrases: {len(mac)}   Windows phrases: {len(win)}   "
      f"Windows vocabulary: {len(win_vocab)} words")
print(f"\nLEADS -- Mac copy with no conceptual echo on Windows ({len(leads)}):\n")
for n, s, miss in leads[:120]:
    print(f"  [{n}] {s!r}")
    print(f"        unknown to Windows: {', '.join(miss)}")
json.dump([{"phrase": s, "missing": m} for _, s, m in leads],
          open(ROOT / "build/qa/parity-leads.json", "w"), indent=1)
