#!/usr/bin/env python3
"""Picture ID (Q7) question set — built from the corpus + E1 enrichment.

For every corpus question whose ANSWER is its source subject AND that subject
has a Commons image (from enrich.json), emit a picture question: the image, a
"What is this?" stem, and the SAME four vetted options (the corpus already
chose type-matched distractors). Keying off answer==subject guarantees the
image actually depicts the correct option.

Output: assets/picture.json — compact array form, one extra element (image URL)
appended after source_url. A separate file (not folded into corpus.json) so the
main corpus contract is untouched and Picture mode loads its own set.

Usage: python3 gen_picture.py
"""
import argparse, hashlib, json, re, urllib.parse


def norm(s):
    s = urllib.parse.unquote(str(s)).replace("_", " ").lower()
    s = re.sub(r"\([^)]*\)", "", s)          # drop disambiguation parens
    s = s.split(",")[0]                        # drop ", Greece" style suffixes
    s = re.sub(r"[^a-z0-9 ]", "", s).strip()
    return s


def answer_is_subject(answer, title):
    a, t = norm(answer), norm(title)
    if not a or not t:
        return False
    return a == t or (len(a) >= 5 and a in t) or (len(t) >= 5 and t in a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="../../assets/corpus.json")
    ap.add_argument("--enrich", default="../../assets/enrich.json")
    ap.add_argument("--out", default="../../assets/picture.json")
    args = ap.parse_args()

    corpus = json.load(open(args.corpus))
    qs = corpus["questions"] if isinstance(corpus, dict) else corpus
    enrich = json.load(open(args.enrich))["entities"]

    out, seen_titles = [], set()
    for q in qs:
        url = q[8]
        if "/wiki/" not in url:
            continue
        title = url.split("/wiki/")[-1]
        ent = enrich.get(title)
        if not ent or "image" not in ent:
            continue
        options, correct = q[2], q[3]
        if not answer_is_subject(options[correct], title):
            continue
        if title in seen_titles:           # one picture question per subject
            continue
        seen_titles.add(title)
        out.append([
            f"picture:{title}", "What is this?", options, correct,
            q[4], q[5], q[7], q[6], url, ent["image"],
        ])

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    with open(args.out, "w") as f:
        f.write(payload)
    print(f"wrote {len(out)} picture questions (version {version}) to {args.out}")
    for q in out[:6]:
        print(" ", q[6], "->", q[2][q[3]], "|", q[9][:64])


if __name__ == "__main__":
    main()
