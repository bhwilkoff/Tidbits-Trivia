#!/usr/bin/env python3
"""Pass A of docs/WINDOWS-PARITY-AUDIT.md — per-surface verb gaps, macOS -> Windows.

Extracts the user-facing verbs from each macOS SwiftUI surface (button/toggle/section/
navigation titles) and reports the ones with no counterpart anywhere in the Windows app.

It deliberately matches on the VERB TEXT, case-insensitively, across the whole Windows
tree rather than file-by-file: parity is "same verb, native idiom", so the Windows home
of a macOS sheet's action is often a different file, a dialog, or a menu.

    python3 tools/audit_windows_parity.py [--all]

Output is a triage list, NOT a verdict. Every hit needs a human judgement:
  - genuine gap          -> file it against docs/WINDOWS-PARITY.md
  - wording difference   -> "Lock it in" vs "Submit order"; add to KNOWN_SYNONYMS
  - Apple-only by design -> Game Center, StoreKit, Sign in with Apple; add to APPLE_ONLY

`--all` skips the two allow-lists and prints the raw diff.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAC = ROOT / "TidbitsTrivia" / "macOS"
WIN = ROOT / "windows" / "Tidbits.App"

# Verbs that exist on Windows under a different, equally-native name.
KNOWN_SYNONYMS = {
    "lock it in": "Submit",
    "lock in order": "Submit order",
    "lock in matches": "Submit matches",
    "reveal answer": "Reveal",
    "clear timer": "Clear",
    "break a tie": "Break tie",
    "print results": "Print",
    "+15s": "+15",
    "+30s": "+30",
    "reset all records": "Reset All Records",
    "host live →": "Host this event",
    "rematch": "Play again",          # Versus rematch rides GameView's Play again
    "resolve tie": "Break tie",       # one dialog on Windows, not two verbs
    "answer sheet (teams)": "Print answer sheet",
    "question pack (host)": "Question pack",
    "reset seen questions": "Seen questions",   # a "Reset" button on a named row
    "gameplay": "Review questions",             # the single setting IS the row header now
    "rename": "Your name",                      # an editable name box, not a Rename button
    "reset to default": "Brand color",          # clearing the hex box IS the reset
    "one-off (not recurring)": "One-off",   # the weekday combo's first item
    "new quick play": "Quick Play",             # plus the Ctrl+N accelerator
    "delete your tidbits account?": "Delete your account?",
    "reset everything?": "Reset all records?",
}

# Deliberately absent — Apple frameworks with no Windows twin (see WINDOWS-PARITY
# "Deferred"). The Windows equivalents are the shared RTDB leaderboard + MS Store.
APPLE_ONLY = {
    "game center",
    "leaderboards & achievements",
    "restore purchases",   # MS Store re-queries entitlement instead
}

VERB_PATTERNS = [
    r'Button\(\s*"([^"]+)"',
    r'Toggle\(\s*"([^"]+)"',
    r'Section\(\s*"([^"]+)"\)',
    r'\.navigationTitle\(\s*"([^"]+)"\)',
    r'confirmationDialog\(\s*"([^"]+)"',
]


# Where a Windows label actually lives: XAML attributes and the `new Button { Content = }`
# object-initialiser style the code-behind uses. Matching raw file text instead would match
# COMMENTS — an early version of this script reported full parity because the word "delete
# account" appeared in a doc comment.
WIN_LABEL_PATTERNS = [
    r'Content\s*=\s*"([^"]+)"',
    r'Text\s*=\s*"([^"]+)"',
    r'Title\s*=\s*"([^"]+)"',
    r'Header\s*=\s*"([^"]+)"',
    r'PlaceholderText\s*=\s*"([^"]+)"',
    r'Watermark\s*=\s*"([^"]+)"',        # the pre-PlaceholderText spelling, still in places
    r'PrimaryButtonText\s*=\s*"([^"]+)"',
    r'CloseButtonText\s*=\s*"([^"]+)"',
]


ITEMS_SOURCE = re.compile(r'ItemsSource\s*=\s*new\[\]\s*\{([^}]*)\}')


def windows_labels() -> set[str]:
    out: set[str] = set()
    for p in WIN.rglob("*"):
        if p.suffix not in (".cs", ".axaml"):
            continue
        if "/obj/" in str(p) or "/bin/" in str(p):
            continue
        s = p.read_text(errors="ignore")
        for pat in WIN_LABEL_PATTERNS:
            for m in re.findall(pat, s):
                out.add(m.strip().rstrip("…").rstrip(":").strip().lower())
        # A ComboBox's choices are user-facing labels too, and they are written as an array
        # literal rather than an attribute — which is how "One-off" read as missing.
        for block in ITEMS_SOURCE.findall(s):
            for item in re.findall(r'"([^"]+)"', block):
                out.add(item.strip().rstrip("…").rstrip(":").strip().lower())
    return out


def verbs_of(path: pathlib.Path) -> set[str]:
    s = path.read_text(errors="ignore")
    out = set()
    for pat in VERB_PATTERNS:
        for m in re.findall(pat, s):
            t = m.strip().rstrip("…").rstrip(":").strip()
            if 2 <= len(t) <= 40 and re.search(r"[A-Za-z]", t) and "\\(" not in t:
                out.add(t)
    return out


def main() -> int:
    raw = "--all" in sys.argv
    win = windows_labels()
    total = gaps = 0
    for path in sorted(MAC.glob("*.swift")):
        verbs = verbs_of(path)
        total += len(verbs)
        missing = []
        for v in sorted(verbs):
            low = v.lower()
            if any(low in w for w in win):
                continue
            if not raw and low in APPLE_ONLY:
                continue
            syn = KNOWN_SYNONYMS.get(low, "").lower()
            if not raw and syn and any(syn in w for w in win):
                continue
            missing.append(v)
        if missing:
            gaps += len(missing)
            print(f"\n{path.name}  ({len(missing)} of {len(verbs)} verbs unmatched)")
            for v in missing:
                print(f"   - {v}")

    print(f"\n{gaps} unmatched verb(s) across {total} macOS verbs.")
    print("Triage each: genuine gap / wording (add to KNOWN_SYNONYMS) / Apple-only "
          "(add to APPLE_ONLY).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
