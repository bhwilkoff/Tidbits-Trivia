#!/usr/bin/env python3
"""Stage D.1 — export corpus_source.sqlite -> assets/enrich.json (Decision 032).

Produces the SAME enrich.json schema the existing bundled-set generators consume
(gen_closest / gen_order / gen_typeanswer / gen_thisorthat / gen_picture), keyed
by underscored title, so those generators get the new ~12k-subject enrichment with
ZERO changes:

  { version, count, entities: { Title_With_Underscores: {
      aliases: [...], image: url, numbers: {label: {value, unit}}, qid } } }

Run AFTER enrich_subjects.py. Writes assets/enrich.json (+ does not copy bundles;
the downstream gen_*.py handle their own copies).

Usage: python3 build_enrich_json.py
"""
import hashlib, json, os, sqlite3

DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "assets", "enrich.json"))

# fact label -> enrich.json number label (others pass through unchanged)
LABEL_MAP = {"birth": "birth_year", "death": "death_year"}


def main():
    con = sqlite3.connect(DB)
    subs = con.execute("SELECT qid, title, image, aliases FROM subject WHERE keep=1").fetchall()
    facts = con.execute("SELECT qid, label, value, unit, kind FROM fact").fetchall()

    numbers_by_qid = {}
    for qid, label, value, unit, kind in facts:
        lbl = LABEL_MAP.get(label, label)
        v = int(value) if float(value).is_integer() else value
        u = "year" if kind == "date" else (unit or "")
        numbers_by_qid.setdefault(qid, {})[lbl] = {"value": v, "unit": u} if u else {"value": v}

    entities = {}
    for qid, title, image, aliases_json in subs:
        ent = {"qid": qid}
        al = json.loads(aliases_json) if aliases_json else []
        if al:
            ent["aliases"] = al
        if image:
            ent["image"] = image
        nums = numbers_by_qid.get(qid)
        if nums:
            ent["numbers"] = nums
        # key by underscored title (matches the /wiki/<Title> URL the corpus emits)
        entities[title.replace(" ", "_")] = ent

    payload = {
        "version": hashlib.sha1(json.dumps(entities, sort_keys=True).encode()).hexdigest()[:12],
        "count": len(entities),
        "entities": entities,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(payload, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))

    n_img = sum(1 for e in entities.values() if "image" in e)
    n_num = sum(1 for e in entities.values() if "numbers" in e)
    n_ali = sum(1 for e in entities.values() if "aliases" in e)
    print(f"wrote {OUT}")
    print(f"  entities: {len(entities):,}  (image {n_img:,} / numbers {n_num:,} / aliases {n_ali:,})")
    con.close()


if __name__ == "__main__":
    main()
