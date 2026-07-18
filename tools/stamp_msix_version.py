#!/usr/bin/env python3
"""Stamp the MSIX manifest version from AppVersion.xcconfig — the same single source
of truth every Apple target uses, so Windows can't silently drift.

The Store's version rule is four segments with the FOURTH RESERVED (must be 0), and
the first segment must be non-zero. So MARKETING_VERSION 1.6.44 -> 1.6.44.0, and
CURRENT_PROJECT_VERSION (the build number) has NOWHERE to live in an MSIX version.
That is a real constraint, not an omission: two different builds of 1.6.44 cannot be
distinguished by MSIX version, so every Store upload needs a MARKETING_VERSION bump.
(The versioning convention already requires bumping on every ship.)

Usage:
  python3 tools/stamp_msix_version.py            # stamp
  python3 tools/stamp_msix_version.py --check    # verify only (CI); non-zero on drift
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
XCCONFIG = ROOT / "AppVersion.xcconfig"
MANIFEST = ROOT / "windows" / "Tidbits.App" / "AppxManifest.xml"
CSPROJ = ROOT / "windows" / "Tidbits.App" / "Tidbits.App.csproj"


def marketing_version() -> str:
    text = XCCONFIG.read_text()
    m = re.search(r"^\s*MARKETING_VERSION\s*=\s*([0-9]+(?:\.[0-9]+)*)\s*$", text, re.M)
    if not m:
        sys.exit(f"MARKETING_VERSION not found in {XCCONFIG}")
    return m.group(1)


def msix_version(marketing: str) -> str:
    parts = [int(p) for p in marketing.split(".")]
    while len(parts) < 3:
        parts.append(0)
    if len(parts) > 3:
        sys.exit(f"MARKETING_VERSION {marketing} has more than 3 segments; "
                 "MSIX reserves the 4th, so there is no room for it.")
    if parts[0] == 0:
        sys.exit(f"MSIX forbids a 0 first segment; MARKETING_VERSION is {marketing}")
    for p in parts:
        if not 0 <= p <= 65535:
            sys.exit(f"MSIX version segments must be 0-65535; got {marketing}")
    return f"{parts[0]}.{parts[1]}.{parts[2]}.0"


def stamp(path: pathlib.Path, pattern: str, want: str, check: bool, label: str) -> None:
    """Match `pattern` (three capture groups: prefix, VALUE, suffix) in `path` and
    check-or-write the value to `want`."""
    text = path.read_text()
    m = re.search(pattern, text, re.S)
    if not m:
        sys.exit(f"No {label} version match in {path}")
    have = m.group(2)
    if check:
        if have != want:
            sys.exit(f"{label} version drift: {path.name} has {have}, AppVersion.xcconfig implies "
                     f"{want}. Run: python3 tools/stamp_msix_version.py")
        print(f"{label} version OK: {have}")
        return
    if have == want:
        print(f"{label} version already {want}")
        return
    path.write_text(text[:m.start(2)] + want + text[m.end(2):])
    print(f"{label} version {have} -> {want}")


def main() -> None:
    check = "--check" in sys.argv
    marketing = marketing_version()
    # MSIX Identity: 4 segments, 4th reserved (1.6.44.0). csproj <Version>: the raw
    # marketing string (1.6.44) — Settings > About reads it via GetName().Version.
    stamp(MANIFEST, r'(<Identity\b[^>]*?\bVersion=")([^"]*)(")', msix_version(marketing), check, "MSIX")
    stamp(CSPROJ, r'(<Version>)([^<]*)(</Version>)', marketing, check, "csproj")


if __name__ == "__main__":
    main()
