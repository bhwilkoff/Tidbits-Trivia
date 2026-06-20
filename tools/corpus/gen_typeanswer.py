#!/usr/bin/env python3
"""Type-the-answer (Q6) — free-recall questions with an accepted-answer set.

Takes corpus describe/cloze questions whose ANSWER is the source subject (so the
clue genuinely points at one nameable thing) and emits a free-text question: the
clue, the canonical answer, and an accepted set = the answer + its Wikidata
aliases (from E1) + the de-underscored title. The client normalizes and matches.

Output: assets/typeanswer.json (+ iOS Resources + Android assets copies).
Row shape: [id, prompt, answer, accepted(list), category, explanation, title, url]

Usage: python3 gen_typeanswer.py
"""
import argparse, hashlib, json, os, re, urllib.parse


def norm(s):
    s = urllib.parse.unquote(str(s)).replace("_", " ").lower()
    s = re.sub(r"\([^)]*\)", "", s)
    s = s.split(",")[0]
    return re.sub(r"[^a-z0-9 ]", "", s).strip()


def answer_is_subject(answer, title):
    a, t = norm(answer), norm(title)
    if not a or not t:
        return False
    return a == t or (len(a) >= 5 and a in t) or (len(t) >= 5 and t in a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/typeanswer.json")
    args = ap.parse_args()

    qs = json.load(open(args.corpus))["questions"]
    enrich = json.load(open(args.enrich))["entities"]

    out, seen = [], set()
    for q in qs:
        tmpl = q[0].split(":")[1] if ":" in q[0] else ""
        if tmpl not in ("describe", "cloze"):
            continue
        if "/wiki/" not in q[8]:
            continue
        title = q[8].split("/wiki/")[-1]
        answer = q[2][q[3]]
        if not answer_is_subject(answer, title) or title in seen:
            continue
        seen.add(title)
        # Accepted set: canonical answer, de-underscored title, Wikidata aliases.
        accepted = {answer, urllib.parse.unquote(title).replace("_", " ")}
        ent = enrich.get(title)
        if ent:
            for a in ent.get("aliases", []):
                accepted.add(a)
        # keep only reasonably short, distinct accepted strings
        acc = [a for a in accepted if a and len(a) <= 60]
        out.append([
            q[0].replace(q[0].split(":")[0] + ":", "type:", 1), q[1], answer, acc,
            q[4], q[6], q[7], q[8],
        ])

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "typeanswer.json")
    and_copy = os.path.join(os.path.dirname(__file__), "..", "..", "android", "app", "src", "main", "assets", "typeanswer.json")
    for path in (args.out, res_copy, and_copy):
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} type-the-answer questions (version {version})")
    for q in out[:4]:
        print("  ", q[1][:70], "=> answer:", q[2], "| accepted:", q[3])


if __name__ == "__main__":
    main()
