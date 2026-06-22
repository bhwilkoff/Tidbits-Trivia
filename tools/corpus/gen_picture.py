#!/usr/bin/env python3
"""Picture ID (Q7) question set — built from the corpus + E1 enrichment.

For every corpus question whose ANSWER is its source subject AND that subject
has a Commons image (from enrich.json), emit a picture question: the image, a
type-aware stem, and the SAME four vetted options (the corpus already chose
type-matched distractors). Keying off answer==subject guarantees the image
actually depicts the correct option.

The stem is built from the subject's one-line description (the text after the
colon in the corpus explanation, e.g. "Finnish ski jumper") so a person is
asked "Who is this Finnish ski jumper?" — never the nonsensical "What is this?"
— and the phrasing rotates across a few natural forms so the mode doesn't ask
the identical question every round. The description never contains the answer's
name, and a leak-guard backstops the person case.

Output: assets/picture.json — compact array form, one extra element (image URL)
appended after source_url. A separate file (not folded into corpus.json) so the
main corpus contract is untouched and Picture mode loads its own set.

Usage: python3 gen_picture.py
"""
import argparse, hashlib, json, os, re, urllib.parse

# --- Type-aware stem construction --------------------------------------------
# Classify the subject from its description, then ask the RIGHT question (a
# person gets "Who is this …?", a place "What city is this?", etc.) with a
# rotating phrasing. Order matters: event/work/animal/org are checked before the
# lifespan-only person signal, because date ranges like "(1914–1924)" appear in
# event descriptions too and would otherwise be misread as a person's lifespan.
_OCCUP = re.compile(r'\b(actor|actress|singer|songwriter|musician|player|footballer|politician|writer|author|poet|painter|physicist|scientist|engineer|director|composer|king|queen|emperor|empress|president|prime minister|philosopher|mathematician|general|admiral|artist|rapper|producer|journalist|economist|chemist|biologist|astronaut|cosmonaut|jumper|skier|boxer|driver|cyclist|wrestler|dancer|architect|novelist|playwright|monarch|saint|pope|chef|model|designer|businessman|businesswoman|entrepreneur|activist|theologian|historian|sociologist|psychologist|presenter|broadcaster|coach|swimmer|sprinter|runner|gymnast|golfer|pianist|guitarist|drummer|bandleader|conductor|sculptor|photographer|filmmaker|screenwriter|comedian|magician|explorer|inventor|nobleman|noblewoman|aristocrat|duke|duchess|prince|princess|sultan|caliph|tsar|chancellor|governor|senator|diplomat|spy|officer|soldier|priest|bishop|cardinal|rabbi|imam|ruler|dictator|revolutionary|reformer|suffragist|abolitionist|critic|essayist|linguist|botanist|geologist|astronomer|archaeologist|anthropologist|surgeon|physician|nurse|lawyer|judge|professor|missionary|founding father|figure)\b', re.I)
_LIFESPAN = re.compile(r'\(\s*(?:born\s+)?\d{3,4}\s*[–\-]\s*\d{0,4}\s*\)|\(\s*born\s+\d{4}\s*\)|\bb\.\s*\d{4}\b|\b\d{4}\s*[–\-]\s*\d{4}\b')
_PLACE = re.compile(r'\b(city|country|capital|town|village|mountain|river|lake|island|islands|region|state|province|county|nation|sea|ocean|desert|peak|volcano|district|municipality|commune|archipelago|territory|kingdom|empire|republic|metropolis|borough|prefecture|canton|valley|harbou?r|fortress|castle|palace|temple|cathedral|university|college|stadium|airport|bridge|tower|park|landmark)\b', re.I)
_EVENT = re.compile(r'\b(war|battle|siege|revolution|genocide|conquest|treaty|massacre|election|movement|uprising|rebellion|crisis|invasion|campaign|disaster|earthquake|pandemic|epidemic|attack|attacks|bombing|riot|protest|coup|expedition|conflict|civil war|clash|raid|revolt|mutiny|purge|famine|plague)\b', re.I)
_WORK = re.compile(r'\b(film|movie|novel|song|album|painting|tv series|series|video game|book|opera|sculpture|play|poem|comic|sitcom|franchise|magazine|newspaper|fairy tale|short story|anthem|symphony|ballet|manga|anime|sonnet|fresco|mural)\b', re.I)
_CREATURE = re.compile(r'\b(birds?|fish|mammals?|insects?|reptiles?|amphibians?|dinosaurs?|snakes?|lizards?|frogs?|sharks?|whales?|dolphins?|spiders?|moths?|butterfl(?:y|ies)|beetles?|snails?|crocodiles?|turtles?|antelopes?|primates?|rodents?|crustaceans?|molluscs?|mollusks?|cetaceans?|flowers?|trees?|fungus|orchids?|ferns?|moss|plants?)\b', re.I)
_TAXON = re.compile(r'\b(species|genus|subspecies|breed)\b', re.I)
_ORG = re.compile(r'\b(company|corporation|organization|organisation|agency|institution|bank|airline|manufacturer|brand|team|club|band|ensemble|orchestra|choir|party|union|association|federation|society|foundation|charity|conglomerate|firm|publisher|studio|network)\b', re.I)
_CLEAN_EVENT = {"war", "battle", "siege", "revolution", "genocide", "conquest", "treaty",
                "massacre", "election", "uprising", "rebellion", "invasion", "campaign",
                "coup", "riot", "bombing", "expedition", "conflict", "civil war", "revolt",
                "mutiny", "purge", "famine", "plague", "movement", "crisis"}


def _stable_pick(rotation, key):
    # Deterministic across runs (built-in hash() is salted per-process, which
    # would reshuffle stems and the version hash on every build).
    h = int(hashlib.md5(key.encode("utf-8")).hexdigest(), 16)
    return rotation[h % len(rotation)]


def _strip_dates(s):
    s = re.sub(r'\s*\([^)]*\)', '', s)
    s = re.split(r'\b(?:from|in|since|during)\s+\d', s, 1)[0]
    s = re.split(r'\b(?:at|of)\s+the\b', s, 1)[0]
    return re.sub(r'\s+', ' ', s).strip().rstrip('.,')


def _lead_role(desc):
    return re.split(r',| and | & ', _strip_dates(desc))[0].strip()


def _classify(desc):
    if _WORK.search(desc): return "work"
    if _EVENT.search(desc): return "event"
    if _TAXON.search(desc) or _CREATURE.search(desc): return "animal"
    if _ORG.search(desc): return "org"
    if _OCCUP.search(desc) or _LIFESPAN.search(desc): return "person"
    if _PLACE.search(desc): return "place"
    return "other"


def _leaks(answer, stem):
    aw = re.findall(r"[a-z]{4,}", re.sub(r"\([^)]*\)", "", answer).lower())
    low = stem.lower()
    return any(w in low for w in aw)


def picture_stem(answer, description, key):
    """A sensible, varied question stem for a picture of `answer`, given its
    one-line `description`. Falls back to a rotating generic when the type is
    unknown — never a wrong interrogative."""
    desc = (description or "").strip()
    if not desc:
        return _stable_pick(["What is this?", "What are we looking at?", "Can you identify this?"], key)
    kind = _classify(desc)
    if kind == "person":
        role = _lead_role(desc)
        if role and 1 <= len(role.split()) <= 4 and not _leaks(answer, role):
            return _stable_pick([f"Who is this {role}?", f"Which {role} is pictured here?",
                                 f"Name this {role}.", f"Can you name this {role}?"], key)
        return _stable_pick(["Who is this person?", "Who is this?", "Can you name this person?"], key)
    if kind == "event":
        m = _EVENT.search(desc); n = m.group(0).lower() if m else None
        if n in _CLEAN_EVENT and not _leaks(answer, n):
            return _stable_pick([f"Which {n} is this?", f"Name this {n}.", "What historical event is this?"], key)
        return _stable_pick(["What historical event is this?", "Which event is depicted here?", "Name this event."], key)
    if kind == "work":
        n = _WORK.search(desc).group(0).lower()
        return _stable_pick([f"What {n} is this?", f"Name this {n}.", f"Which {n} is this?"], key)
    if kind == "animal":
        m = _CREATURE.search(desc)
        n = (m.group(0).lower().rstrip("s") if m else "species")
        n = "butterfly" if n in ("butterfl", "butterfli") else n
        return _stable_pick([f"What {n} is this?", f"Name this {n}.", "What is this?"], key)
    if kind == "org":
        n = _ORG.search(desc).group(0).lower()
        return _stable_pick([f"What {n} is this?", f"Name this {n}.", "What is this?"], key)
    if kind == "place":
        n = _PLACE.search(desc).group(0).lower()
        return _stable_pick([f"What {n} is this?", f"Name this {n}.", f"Which {n} is shown here?"], key)
    return _stable_pick(["What is this?", "What are we looking at?", "Can you identify this?"], key)


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
        explanation = q[6] if len(q) > 6 else ""
        desc = explanation.split(":", 1)[1].strip() if ":" in explanation else ""
        stem = picture_stem(options[correct], desc, q[0])
        # Same column order as corpus.json (id,prompt,options,correct,cat,diff,
        # explanation,source_title,source_url) + a 10th element: the image URL.
        out.append([
            q[0].replace("corpus:", "picture:", 1), stem, options, correct,
            q[4], q[5], q[6], q[7], q[8], ent["image"],
        ])

    body = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
    version = hashlib.md5(body.encode()).hexdigest()[:12]
    payload = f'{{"version":"{version}","count":{len(out)},"questions":{body}}}'
    # Web + Android read assets/; iOS/tvOS bundle a Resources/ copy (their corpus
    # is SQLite, so picture.json rides alongside as the Picture-mode source).
    res_copy = os.path.join(os.path.dirname(__file__), "..", "..", "TidbitsTrivia", "Resources", "picture.json")
    for path in (args.out, res_copy):
        with open(path, "w") as f:
            f.write(payload)
    print(f"wrote {len(out)} picture questions (version {version}) to {args.out} + Resources")
    for q in out[:6]:
        print(" ", q[6], "->", q[2][q[3]], "|", q[9][:64])


if __name__ == "__main__":
    main()
