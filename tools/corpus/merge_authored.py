#!/usr/bin/env python3
"""Merge agent-authored + verified questions into a per-type corpus file.

Track B (2026-07): fills the (category × type) coverage holes surfaced by the
question-load audit. Reads a JSON file of VERIFIED survivors from the authoring
workflow and appends them, in the exact per-type row schema, to the type file —
then syncs the three tracked copies (assets / iOS Resources / Android assets;
Windows picks it up via its Content link). Idempotent: dedupes by a content key
so re-runs don't duplicate.

Usage: python3 merge_authored.py <type> <survivors.json>
  <type> = oddoneout | match | enumerate
  survivors.json = {"survivors": [ {type-specific fields...}, ... ]}
"""
import hashlib, json, os, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
COPIES = {
    "assets": "assets",
    "ios": os.path.join("TidbitsTrivia", "Resources"),
    "android": os.path.join("android", "app", "src", "main", "assets"),
}


def h(*parts):
    return hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:14]


def wiki_url(title):
    return f"https://en.wikipedia.org/wiki/{(title or '').replace(' ', '_')}" if title else ""


def to_oddoneout(q):
    # [id, prompt, options(4), correctIndex, category, difficulty, explanation, title, url]
    cat = q["category"]
    ans = q["options"][q["answerIndex"]]
    expl = q.get("outlierReason") or f"{ans} is the odd one out."
    return [f"odd:{cat}:{h(q['prompt'], ans)}", q["prompt"], q["options"], q["answerIndex"],
            cat, 3, expl, q.get("sourceTitle", ""), wiki_url(q.get("sourceTitle"))]


def to_match(q):
    # [id, prompt, keys[], values[], category, explanation, title, url]
    cat = q["category"]
    keys = [p["left"] for p in q["pairs"]]
    vals = [p["right"] for p in q["pairs"]]
    expl = " · ".join(f"{k} → {v}" for k, v in zip(keys, vals))
    return [f"match:{cat}:{h(q['prompt'], *keys)}", q["prompt"], keys, vals, cat, expl,
            q.get("sourceTitle", ""), wiki_url(q.get("sourceTitle"))]


def to_enumerate(q):
    # [id, prompt, groups[[canonical,alias...]], category, seconds, url]
    groups = []
    for m in q["members"]:
        if isinstance(m, str):
            groups.append([m])
        elif isinstance(m, dict):
            groups.append([m["name"]] + list(m.get("aliases", [])))
        else:
            groups.append(list(m))
    return [f"enum:{q['category']}:{h(q['prompt'])}", q["prompt"], groups, q["category"], 60,
            wiki_url(q.get("sourceTitle"))]


MAP = {"oddoneout": to_oddoneout, "match": to_match, "enumerate": to_enumerate}


def dedupe_key(row, typ):
    # prompt + first answer/pair/member, lowercased — stable across id churn.
    if typ == "enumerate":
        return (row[1].lower())
    return (row[1].lower(), json.dumps(row[2], ensure_ascii=False).lower())


def main():
    typ, survivors_path = sys.argv[1], sys.argv[2]
    fn = f"{typ}.json"
    src = json.load(open(survivors_path))
    survivors = src["survivors"] if isinstance(src, dict) else src

    base = os.path.join(ROOT, COPIES["assets"], fn)
    data = json.load(open(base))
    rows = data["questions"]
    existing = {dedupe_key(r, typ) for r in rows}

    added = 0
    for q in survivors:
        row = MAP[typ](q)
        k = dedupe_key(row, typ)
        if k in existing:
            continue
        existing.add(k)
        rows.append(row)
        added += 1

    data["count"] = len(rows)
    # Content-hash version so any change busts client caches (web keys on version).
    ver = hashlib.sha1(json.dumps(rows, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:12]
    data["version"] = ver
    body = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    for name, rel in COPIES.items():
        p = os.path.join(ROOT, rel, fn)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(body)
    print(f"{typ}: +{added} authored (total {len(rows)}, v{ver}); synced {list(COPIES)}")


if __name__ == "__main__":
    main()
