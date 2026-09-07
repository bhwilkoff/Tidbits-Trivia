#!/usr/bin/env python3
"""Build tools/live-event/golden.tidbits (LIVE-PACKAGE-FORMAT §7.1) from the
event golden plus two tiny synthetic media files. Deterministic: run it twice
and the bytes are identical, so a change to the fixture is always a diff."""
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import live_package as lp  # noqa: E402

HERE = Path(__file__).resolve().parent

def png_1x1(rgb=(255, 92, 53)):
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    raw = b"\x00" + bytes(rgb)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")

def wav_beep(samples=800, rate=8000):
    import math
    pcm = b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(samples))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE" + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", len(pcm))
    return hdr + pcm

doc = json.loads((HERE / "golden.tidbitsevent.json").read_text())
png = lp.Media(png_1x1(), "png", "golden-picture.png", "https://example.test/golden-picture.png", "Golden Studio", "CC0")
wav = lp.Media(wav_beep(), "wav", "golden-beep.wav")
r0 = doc["event"]["rounds"][0]
r0["questions"][0]["imageURL"] = png.ref                      # a packaged picture (§3.1)
r0["questions"][1]["imageURL"] = "https://example.test/by-url.jpg"   # a picture left by URL (§3.3)
r0["audio"] = [wav.id] + [None] * (len(r0["questions"]) - 1)    # one audio slot (§3.2)
doc["droppedClipCount"] = 0
doc["app"] = "Tidbits Trivia (golden)"
out = HERE / "golden.tidbits"
lp.write(out, doc, [png, wav], kind="event", created_by="tools/live-event/make_golden_package.py",
         created_at="2026-09-07T00:00:00Z")
print(out, out.stat().st_size, "bytes", "png", png.id, "wav", wav.id)
