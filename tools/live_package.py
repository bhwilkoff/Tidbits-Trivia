#!/usr/bin/env python3
"""The Tidbits package (`.tidbits`) — reference reader/writer.

    python3 tools/live_package.py pack   Night.tidbitsevent.json -o Night.tidbits [--fetch] [--kind event|bank]
    python3 tools/live_package.py unpack Night.tidbits -o Night.unpacked/
    python3 tools/live_package.py inspect Night.tidbits

Contract: docs/LIVE-PACKAGE-FORMAT.md. This module is what the golden fixture
is built with and what the importers (`kahoot_import.py --package`) call; the
Mac and Windows apps carry their own implementations and must open what this
writes (and vice versa — the golden proves it).

`pack` takes a LIVE-EVENT-FILE document. A question `imageURL` that is a LOCAL
file path (relative to the document's folder) is embedded and rewritten to
`tidbits-media:<id>`; an https URL is embedded too when `--fetch` is given
(keeping the URL as `sourceURL`), otherwise left as is. A round may carry
`audio` / `video` arrays of local paths (one slot per question, null for
none); they are embedded the same way and rewritten to ids.
"""
import argparse
import hashlib
import io
import json
import mimetypes
import os
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

FORMAT = "com.learningischange.tidbits.package"
VERSION = 1
MIMETYPE = "application/vnd.learningischange.tidbits+zip"
EVENT_FORMAT = "com.learningischange.tidbits.live-event"
SCHEME = "tidbits-media:"

# §2.5 — the allow-list. A package is not a general-purpose archive.
KINDS = {
    "image": {"png", "jpg", "jpeg", "gif", "webp", "svg"},
    "audio": {"mp3", "m4a", "wav", "aac", "ogg", "flac"},
    "video": {"mp4", "mov", "m4v", "webm"},
}
MIME = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "webp": "image/webp", "svg": "image/svg+xml", "mp3": "audio/mpeg", "m4a": "audio/mp4",
        "wav": "audio/wav", "aac": "audio/aac", "ogg": "audio/ogg", "flac": "audio/flac",
        "mp4": "video/mp4", "mov": "video/quicktime", "m4v": "video/x-m4v", "webm": "video/webm"}
EXT_FOR_MIME = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
                "image/svg+xml": "svg", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/wav": "wav",
                "audio/x-wav": "wav", "audio/aac": "aac", "audio/ogg": "ogg", "audio/flac": "flac",
                "video/mp4": "mp4", "video/quicktime": "mov", "video/x-m4v": "m4v", "video/webm": "webm"}

# A fixed timestamp so a package built from the same inputs is byte-identical
# (the golden must be reproducible).
FIXED_TIME = (2026, 1, 1, 0, 0, 0)


class PackageError(Exception):
    pass


def kind_for(ext):
    for k, exts in KINDS.items():
        if ext in exts:
            return k
    return None


class Media:
    """One media file, content-addressed."""
    def __init__(self, data, ext, original_name="", source_url="", credit="", license_=""):
        ext = ext.lower().lstrip(".")
        if ext == "jpeg":
            ext = "jpg"
        kind = kind_for(ext)
        if kind is None:
            raise PackageError(f"{original_name or ext}: not an allowed media type (§2.5)")
        self.data = data
        self.ext = ext
        self.kind = kind
        self.sha256 = hashlib.sha256(data).hexdigest()
        self.id = self.sha256[:32]
        self.original_name = original_name
        self.source_url = source_url
        self.credit = credit
        self.license = license_

    @property
    def path(self):
        return f"media/{self.id}.{self.ext}"

    def entry(self):
        e = {"id": self.id, "path": self.path, "sha256": self.sha256, "bytes": len(self.data),
             "mime": MIME[self.ext], "kind": self.kind}
        if self.original_name:
            e["originalName"] = self.original_name
        if self.source_url:
            e["sourceURL"] = self.source_url
        if self.credit:
            e["credit"] = self.credit
        if self.license:
            e["license"] = self.license
        return e

    @property
    def ref(self):
        return SCHEME + self.id


def media_from_file(path, source_url="", credit="", license_=""):
    p = Path(path)
    return Media(p.read_bytes(), p.suffix, p.name, source_url, credit, license_)


def media_from_url(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "TidbitsTrivia-LivePackage/1"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        data = r.read()
    ext = EXT_FOR_MIME.get(ctype)
    if ext is None:
        raise PackageError(f"{url}: answered {ctype!r}, not an allowed media type")
    return Media(data, ext, url.rsplit("/", 1)[-1][:80], url)


def write(out_path, doc, media, kind="event", created_by="tools/live_package.py", created_at=None):
    """Write a package. `doc` is the event document (already referencing ids);
    `media` a list of Media."""
    if doc.get("format") != EVENT_FORMAT:
        raise PackageError("event document is not a Tidbits Live event")
    by_id = {}
    for m in media:
        by_id[m.id] = m          # de-duplicates identical bytes (§2.4)
    manifest = {
        "format": FORMAT, "version": VERSION, "kind": kind,
        "title": doc.get("event", {}).get("name", ""),
        "createdAt": created_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "createdBy": created_by,
        "media": [by_id[i].entry() for i in sorted(by_id)],
    }
    _check_refs(doc, by_id)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        # §1.2: mimetype first, stored, so the file is sniffable.
        z.writestr(zipfile.ZipInfo("mimetype", FIXED_TIME), MIMETYPE, compress_type=zipfile.ZIP_STORED)
        z.writestr(zipfile.ZipInfo("manifest.json", FIXED_TIME),
                   json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
                   compress_type=zipfile.ZIP_DEFLATED)
        z.writestr(zipfile.ZipInfo("event.json", FIXED_TIME),
                   json.dumps(doc, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
                   compress_type=zipfile.ZIP_DEFLATED)
        for i in sorted(by_id):
            m = by_id[i]
            # Media is already compressed; store it so the file is a plain copy.
            z.writestr(zipfile.ZipInfo(m.path, FIXED_TIME), m.data, compress_type=zipfile.ZIP_STORED)
    Path(out_path).write_bytes(buf.getvalue())
    return manifest


def _refs(doc):
    for r in doc.get("event", {}).get("rounds", []):
        for q in r.get("questions", []):
            u = q.get("imageURL") or ""
            if u.startswith(SCHEME):
                yield u[len(SCHEME):], f"{q.get('id')}"
        for key in ("audio", "video"):
            for i, ref in enumerate(r.get(key) or []):
                if ref:   # §3.2: a bare id; a scheme-prefixed one is tolerated
                    yield (ref[len(SCHEME):] if ref.startswith(SCHEME) else ref), f"{r.get('title')} {key} #{i + 1}"


def _check_refs(doc, by_id):
    missing = [(ref, where) for ref, where in _refs(doc) if ref not in by_id]
    if missing:
        raise PackageError("references without media: " + ", ".join(f"{w} -> {r}" for r, w in missing))


def read(path, verify=True):
    """Open a package. Returns (manifest, doc, {id: bytes})."""
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        raise PackageError("That file is not a Tidbits package (not a zip).")
    names = set(z.namelist())
    if "mimetype" not in names or z.read("mimetype").decode("utf-8", "replace").strip() != MIMETYPE:
        raise PackageError("That file is not a Tidbits package.")
    if "manifest.json" not in names or "event.json" not in names:
        raise PackageError("That package is missing its manifest or event document.")
    manifest = json.loads(z.read("manifest.json"))
    if manifest.get("format") != FORMAT:
        raise PackageError("That file is not a Tidbits package.")
    if int(manifest.get("version", 0)) > VERSION:
        raise PackageError(f"That package was saved by a newer version of Tidbits (format {manifest['version']}).")
    doc = json.loads(z.read("event.json"))
    if doc.get("format") != EVENT_FORMAT:
        raise PackageError("The package's event document is not a Tidbits Live event.")
    media = {}
    for e in manifest.get("media", []):
        p = e.get("path", "")
        if p not in names:
            raise PackageError(f"Media missing from the package: {e.get('originalName') or p}")
        data = z.read(p)
        if verify and hashlib.sha256(data).hexdigest() != e.get("sha256"):
            raise PackageError(f"Media does not match its hash: {e.get('originalName') or p}")
        media[e["id"]] = data
    return manifest, doc, media


def pack_document(doc_path, out_path, fetch=False, kind="event", created_by="tools/live_package.py"):
    """`pack`: embed local (and, with fetch, https) media referenced by a document."""
    doc_path = Path(doc_path)
    doc = json.loads(doc_path.read_text())
    if doc.get("format") != EVENT_FORMAT:
        raise PackageError(f"{doc_path.name} is not a Tidbits Live event document")
    root = doc_path.parent
    media, notes = [], []

    def embed_ref(value, where, as_id=False):
        # Pictures are `tidbits-media:<id>` URLs (§3.1); clip slots are bare ids (§3.2).
        r = _embed(value, where)
        return (r[len(SCHEME):] if as_id and r and r.startswith(SCHEME) else r)

    def _embed(value, where):
        if not value or value.startswith(SCHEME):
            return value
        if value.startswith("http://") or value.startswith("https://"):
            if not fetch:
                return value
            try:
                m = media_from_url(value)
            except Exception as e:  # noqa: BLE001
                notes.append(f"{where}: could not fetch {value} ({e}); left as a URL")
                return value
            media.append(m)
            return m.ref
        local = value[7:] if value.startswith("file://") else value
        p = (root / local) if not os.path.isabs(local) else Path(local)
        if not p.exists():
            notes.append(f"{where}: {value} is not a file next to the document; left as is")
            return value
        try:
            m = media_from_file(p)
        except PackageError as e:
            notes.append(f"{where}: {e}; left as is")
            return value
        media.append(m)
        return m.ref

    for r in doc.get("event", {}).get("rounds", []):
        for q in r.get("questions", []):
            if q.get("imageURL"):
                q["imageURL"] = embed_ref(q["imageURL"], q.get("id", "?"))
        for key in ("audio", "video"):
            if r.get(key):
                r[key] = [embed_ref(v, f"{r.get('title')} {key} #{i + 1}", as_id=True) if v else None
                          for i, v in enumerate(r[key])]
    manifest = write(out_path, doc, media, kind=kind, created_by=created_by)
    return manifest, notes


def unpack(path, out_dir):
    manifest, doc, media = read(path)
    out = Path(out_dir); (out / "media").mkdir(parents=True, exist_ok=True)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    (out / "event.json").write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    for e in manifest["media"]:
        (out / e["path"]).write_bytes(media[e["id"]])
    return manifest


def inspect(path):
    manifest, doc, media = read(path)
    ev = doc["event"]
    print(f"{Path(path).name}: {manifest['kind']} \"{manifest.get('title')}\" by {manifest.get('createdBy')} at {manifest.get('createdAt')}")
    total = sum(len(r.get("questions", [])) for r in ev.get("rounds", []))
    print(f"  {len(ev.get('rounds', []))} round(s), {total} questions, {len(manifest['media'])} media file(s), "
          f"{sum(e['bytes'] for e in manifest['media']) / 1e6:.1f} MB")
    for r in ev.get("rounds", []):
        pics = sum(1 for q in r.get("questions", []) if (q.get("imageURL") or "").startswith(SCHEME))
        ext = sum(1 for q in r.get("questions", []) if (q.get("imageURL") or "").startswith("http"))
        clips = sum(1 for k in ("audio", "video") for v in (r.get(k) or []) if v)
        print(f"  - {r.get('title')}: {len(r.get('questions', []))} x {r.get('format')}, "
              f"{pics} packaged picture(s), {ext} by URL, {clips} clip(s)")
    for e in manifest["media"]:
        print(f"    {e['kind']:5} {e['id']} {e['bytes']:>9} B {e['mime']:12} {e.get('originalName', '')}"
              + (f"  <- {e['sourceURL']}" if e.get("sourceURL") else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack"); p.add_argument("document"); p.add_argument("-o", "--output", required=True)
    p.add_argument("--fetch", action="store_true", help="download https pictures into the package")
    p.add_argument("--kind", choices=["event", "bank"], default="event")
    u = sub.add_parser("unpack"); u.add_argument("package"); u.add_argument("-o", "--output", required=True)
    i = sub.add_parser("inspect"); i.add_argument("package")
    a = ap.parse_args()
    try:
        if a.cmd == "pack":
            manifest, notes = pack_document(a.document, a.output, fetch=a.fetch, kind=a.kind)
            print(f"{a.output}: {len(manifest['media'])} media file(s)")
            for n in notes:
                print(f"  ! {n}")
        elif a.cmd == "unpack":
            m = unpack(a.package, a.output); print(f"{a.output}: {len(m['media'])} media file(s)")
        else:
            inspect(a.package)
    except PackageError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
