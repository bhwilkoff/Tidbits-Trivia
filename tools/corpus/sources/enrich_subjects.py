#!/usr/bin/env python3
"""Stage B — enrich the curated subjects with Wikidata facts (Decision 032).

For each subject QID in corpus_source.sqlite, fetch the Wikidata entity (batched
wbgetentities — targeted, since the curated set is ~12k, not millions) and extract
exactly what the game types need:

  - aliases          -> Type-the-answer accepted set (Q6), Name-as-Many (Q8)
  - P31/P106 type    -> the 7 app categories + type-matched distractors / Odd-one-out
  - numeric facts    -> Closest Call (M5), "which is bigger" (Q1)
  - date facts       -> Ordering (Q4), "which came first" (Q1)
  - 1:1 relations    -> Matching (Q5)
  - P18 image        -> Picture ID (Q7)
  - sitelinks        -> durability signal (blends with Qrank for selection)

Also CATEGORIZES each subject (P106 occupation for humans, else P31) into one of
the app's 7 domains, and applies an appropriateness gate (mission alignment).

Writes tables: fact(qid, prop, value, unit, kind), relation(qid, prop, target_qid,
target_label), and updates subject.category / subject.sitelinks / subject.keep.

Usage: python3 enrich_subjects.py [--limit N]
"""
import argparse, os, sqlite3, sys, time, json, urllib.parse, urllib.request

WD = "https://www.wikidata.org/w/api.php"
UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"
DB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "corpus_source.sqlite"))

# ---- category mapping: Wikidata type/occupation QID -> app domain -----------
SCREEN = "screen"; MUSIC = "music"; SPORTS = "sports"; ARTS = "arts"
SCIENCE = "science"; GEOGRAPHY = "geography"; HISTORY = "history"
BUSINESS = "business"

# P106 occupation (for humans) -> domain
OCCUPATION = {
    # music
    "Q639669": MUSIC, "Q177220": MUSIC, "Q36834": MUSIC, "Q855091": MUSIC,
    "Q488205": MUSIC, "Q183945": MUSIC, "Q158852": MUSIC, "Q12800682": MUSIC,
    "Q753110": MUSIC, "Q2252262": MUSIC, "Q486748": MUSIC,
    # screen
    "Q33999": SCREEN, "Q2526255": SCREEN, "Q3282637": SCREEN, "Q28389": SCREEN,
    "Q10800557": SCREEN, "Q2405480": SCREEN, "Q947873": SCREEN, "Q578109": SCREEN,
    # sports
    "Q2066131": SPORTS, "Q937857": SPORTS, "Q3665646": SPORTS, "Q10833314": SPORTS,
    "Q19204627": SPORTS, "Q11513337": SPORTS, "Q12299841": SPORTS, "Q11338576": SPORTS,
    "Q628099": SPORTS, "Q13141064": SPORTS,
    # arts (writers / visual / philosophy)
    "Q36180": ARTS, "Q49757": ARTS, "Q6625963": ARTS, "Q1028181": ARTS,
    "Q1281618": ARTS, "Q42973": ARTS, "Q4964182": ARTS, "Q482980": ARTS,
    "Q214917": ARTS, "Q11569986": ARTS, "Q1930187": ARTS, "Q3658608": ARTS,
    # science
    "Q901": SCIENCE, "Q169470": SCIENCE, "Q593644": SCIENCE, "Q864503": SCIENCE,
    "Q170790": SCIENCE, "Q11063": SCIENCE, "Q205375": SCIENCE, "Q81096": SCIENCE,
    "Q188094": SCIENCE, "Q39631": SCIENCE, "Q2374149": SCIENCE, "Q1622272": SCIENCE,
    # history (rulers / politics / military)
    "Q82955": HISTORY, "Q116": HISTORY, "Q47064": HISTORY, "Q189290": HISTORY,
    "Q372436": HISTORY, "Q14211776": HISTORY, "Q15967159": HISTORY, "Q193391": HISTORY,
    "Q842782": HISTORY, "Q3242115": HISTORY,
    "Q2304859": HISTORY, "Q1097498": HISTORY, "Q11900058": HISTORY,  # sovereign/ruler/explorer
    "Q10871364": SPORTS, "Q11774891": SPORTS,                        # baseball / ice-hockey player
    # business (2026-07-25: entrepreneur/businessperson used to be deliberately
    # left unmapped because there was no home category for them -- now there is.
    "Q131524": BUSINESS,   # entrepreneur
    "Q43845": BUSINESS,    # businessperson
    "Q484876": BUSINESS,   # investor
    "Q1113723": BUSINESS,  # chief executive officer
    # --- NULL-coverage round (2026-07): top uncovered occupations among the
    #     7,708 uncategorized kept subjects. Only domain-unambiguous roles added;
    #     genuinely-ambiguous ones (socialite,
    #     lawyer, model, criminal/serial-killer, generic clergy) left UNMAPPED so
    #     a better-matching occupation wins, else the subject stays NULL.
    # sports
    "Q10349745": SPORTS,  # racing automobile driver
    "Q10841764": SPORTS,  # Formula One driver
    "Q11607585": SPORTS,  # mixed martial arts fighter
    "Q13474373": SPORTS,  # professional wrestler
    "Q13381572": SPORTS,  # artistic gymnast
    "Q11303721": SPORTS,  # golfer
    "Q2309784": SPORTS,   # sport cyclist
    "Q14089670": SPORTS,  # rugby union player
    "Q12369333": SPORTS,  # amateur wrestler
    "Q10843402": SPORTS,  # swimmer
    # science
    "Q11631": SCIENCE,    # astronaut
    "Q82594": SCIENCE,    # computer scientist
    "Q5482740": SCIENCE,  # programmer
    "Q4773904": SCIENCE,  # anthropologist
    "Q212980": SCIENCE,   # psychologist
    "Q211346": SCIENCE,   # psychiatrist
    # arts (writers / visual / design / performing)
    "Q3501317": ARTS,     # fashion designer
    "Q33231": ARTS,       # photographer
    "Q1323191": ARTS,     # costume designer
    "Q5716684": ARTS,     # dancer (performing art)
    # DELIBERATELY NOT MAPPED (too broad — flip multi-role people who merely
    # wrote: a general/scientist with a memoir is not "arts"): autobiographer
    # Q18814623, non-fiction writer Q15980158, theologian Q1234713, artist Q483501.
    # music
    "Q2865819": MUSIC,    # opera singer
    # screen
    "Q17125263": SCREEN,  # YouTuber
    "Q488111": SCREEN,    # pornographic actor (actor -> screen; keep gate is separate)
    # history (nobility / military / regency)
    "Q2478141": HISTORY,  # aristocrat
    "Q1402561": HISTORY,  # military leader
    "Q477406": HISTORY,   # regent
    "Q12097": HISTORY,    # king
    "Q38239859": HISTORY, # army officer
    "Q10669499": HISTORY, # naval officer
    "Q4991371": HISTORY,  # soldier
    "Q19934710": HISTORY, # air force officer
}
# P31 instance-of -> domain (non-humans)
INSTANCE = {
    # screen
    "Q11424": SCREEN, "Q5398426": SCREEN, "Q1259759": SCREEN, "Q24856": SCREEN,
    "Q24862": SCREEN, "Q506240": SCREEN, "Q202866": SCREEN, "Q1366112": SCREEN,
    "Q229390": SCREEN, "Q93204": SCREEN,
    # music
    "Q482994": MUSIC, "Q134556": MUSIC, "Q7366": MUSIC, "Q215380": MUSIC,
    "Q2088357": MUSIC, "Q105543609": MUSIC, "Q207628": MUSIC,
    "Q1067164": MUSIC, "Q34379": MUSIC,
    # arts
    "Q571": ARTS, "Q7725634": ARTS, "Q3305213": ARTS, "Q860861": ARTS,
    "Q47461344": ARTS, "Q25379": ARTS, "Q1107656": ARTS, "Q838948": ARTS,
    "Q8261": ARTS, "Q149918": ARTS, "Q1760610": ARTS,
    # geography
    "Q6256": GEOGRAPHY, "Q515": GEOGRAPHY, "Q4022": GEOGRAPHY, "Q8502": GEOGRAPHY,
    "Q23397": GEOGRAPHY, "Q165": GEOGRAPHY, "Q23442": GEOGRAPHY, "Q46831": GEOGRAPHY,
    "Q33837": GEOGRAPHY, "Q5107": GEOGRAPHY, "Q1549591": GEOGRAPHY, "Q35657": GEOGRAPHY,
    "Q3957": GEOGRAPHY, "Q532": GEOGRAPHY, "Q82794": GEOGRAPHY, "Q34876": GEOGRAPHY,
    "Q39816": GEOGRAPHY, "Q8514": GEOGRAPHY, "Q40080": GEOGRAPHY, "Q44782": GEOGRAPHY,
    # science
    "Q11344": SCIENCE, "Q16521": SCIENCE, "Q11173": SCIENCE, "Q634": SCIENCE,
    "Q3863": SCIENCE, "Q523": SCIENCE, "Q11173": SCIENCE, "Q2095": SCIENCE,
    "Q12136": SCIENCE, "Q7187": SCIENCE, "Q11015": SCIENCE, "Q8054": SCIENCE,
    "Q43229": SCIENCE, "Q336": SCIENCE, "Q413": SCIENCE,
    # history
    "Q198": HISTORY, "Q178561": HISTORY, "Q13418847": HISTORY, "Q1190554": HISTORY,
    "Q3024240": HISTORY, "Q10931": HISTORY, "Q7269": HISTORY, "Q41397": HISTORY,
    "Q188055": HISTORY, "Q186361": HISTORY, "Q1656682": HISTORY, "Q645883": HISTORY,
    "Q3199915": HISTORY, "Q15275719": HISTORY, "Q49773": HISTORY, "Q175331": HISTORY,
    "Q8065": HISTORY, "Q3839081": HISTORY, "Q750215": HISTORY, "Q43229": HISTORY,
    # --- extended geography ---
    "Q3624078": GEOGRAPHY, "Q486972": GEOGRAPHY, "Q1549591": GEOGRAPHY, "Q15284": GEOGRAPHY,
    "Q5119": GEOGRAPHY, "Q200250": GEOGRAPHY, "Q1093829": GEOGRAPHY, "Q41176": GEOGRAPHY,
    "Q811979": GEOGRAPHY, "Q16970": GEOGRAPHY, "Q33506": GEOGRAPHY, "Q570116": GEOGRAPHY,
    "Q839954": GEOGRAPHY, "Q22698": GEOGRAPHY, "Q12518": GEOGRAPHY, "Q44782": GEOGRAPHY,
    "Q23413": GEOGRAPHY, "Q12280": GEOGRAPHY, "Q11303": GEOGRAPHY, "Q10864048": GEOGRAPHY,
    "Q702492": GEOGRAPHY, "Q188509": GEOGRAPHY, "Q34442": GEOGRAPHY, "Q1248784": GEOGRAPHY,
    # --- extended science ---
    "Q12140": SCIENCE, "Q483247": SCIENCE, "Q34740": SCIENCE, "Q205663": SCIENCE,
    "Q39546": SCIENCE, "Q11023": SCIENCE, "Q42889": SCIENCE, "Q1420": SCIENCE,
    "Q101352": SCIENCE, "Q7239": SCIENCE, "Q729": SCIENCE, "Q55983715": SCIENCE,
    # --- extended arts ---
    "Q7889": ARTS, "Q11410": ARTS, "Q1792379": ARTS, "Q968159": ARTS,
    "Q1107656": ARTS, "Q4502142": ARTS, "Q1004": ARTS, "Q245068": ARTS,
    "Q7725310": SCREEN, "Q15416": SCREEN,
    # --- extended music ---
    "Q188451": MUSIC, "Q20502": MUSIC,
    # --- from the type diagnostic (frequent uncategorized non-humans) ---
    "Q23038290": SCIENCE,   # fossil taxon (megalodon, Spinosaurus)
    "Q113145171": SCIENCE,  # type of chemical entity (oxycodone)
    "Q112193867": SCIENCE,  # class of disease (Crohn's)
    "Q17524420": HISTORY,   # aspect of history (history of Ukraine)
    # --- second recategorize round ---
    "Q17544377": HISTORY,   # history of a country/state
    "Q8465": HISTORY, "Q831663": HISTORY, "Q12909644": HISTORY, "Q23847174": HISTORY,
    "Q8928": SCIENCE, "Q2996394": SCIENCE, "Q11862829": SCIENCE, "Q65943": SCIENCE,
    "Q15056993": SCIENCE, "Q47154513": SCIENCE,
    "Q58483083": ARTS,      # dramatico-musical work (Hamilton, Wicked)
    "Q31629": SPORTS,       # type of sport
    "Q5503": GEOGRAPHY,     # rapid transit
    "Q5741069": MUSIC,      # rock band
    # business (2026-07-25: brands/companies used to be deliberately left
    # unmapped because there was no home category -- now there is. NOTE: this
    # also fixes the root cause of the "company defaults to music" bug --
    # Q4830453 (business) was wrongly mapped to MUSIC above and has been moved.
    "Q4830453": BUSINESS,   # business
    "Q783794": BUSINESS,    # company
    "Q6881511": BUSINESS,   # enterprise
    "Q431289": BUSINESS,    # brand
    "Q161726": BUSINESS,    # corporation
    "Q615536": BUSINESS,    # start-up company
    # --- NULL-coverage round (2026-07): top uncovered non-human P31 types.
    #     Ambiguous / no-home types (websites, public
    #     universities, airlines, currencies, languages, writing systems, foods,
    #     holidays, months, ethnic groups, abstract concepts/fields) left UNMAPPED.
    # sports
    "Q476028": SPORTS,      # association football club
    "Q27020041": SPORTS,    # sports season
    "Q18608583": SPORTS,    # recurring sporting event
    "Q135408445": SPORTS,   # men's national association football team
    "Q2312410": SPORTS,     # sports discipline
    "Q1478437": SPORTS,     # association football competition
    "Q15991303": SPORTS,    # association football league
    "Q17317604": SPORTS,    # professional wrestling event
    "Q15991290": SPORTS,    # professional sports league
    "Q623109": SPORTS,      # sports league
    "Q847017": SPORTS,      # sports club
    # screen (film / TV / games; by medium for characters)
    "Q15773347": SCREEN,    # film character
    "Q15773317": SCREEN,    # television character
    "Q15711870": SCREEN,    # animated character
    "Q1569167": SCREEN,     # video game character
    "Q7058673": SCREEN,     # video game series
    "Q117467246": SCREEN,   # animated television series
    "Q3464665": SCREEN,     # television series season
    "Q196600": SCREEN,      # media franchise
    # arts (comics / literature / drama / photograph; by medium for characters)
    "Q21198342": ARTS,      # manga series (comics, matches Q1004 comics -> arts)
    "Q3658341": ARTS,       # literary character
    "Q1114461": ARTS,       # comics character
    "Q1667921": ARTS,       # novel series
    "Q116476516": ARTS,     # dramatic work
    "Q125191": ARTS,        # photograph
    "Q223393": ARTS,        # literary genre
    # music
    "Q641066": MUSIC,       # girl group
    "Q110295396": MUSIC,    # type of musical instrument
    # geography (subnational units / regions / parks / flags)
    "Q12443800": GEOGRAPHY, # state of India
    "Q15149663": GEOGRAPHY, # state of Mexico
    "Q150093": GEOGRAPHY,   # voivodeship of Poland
    "Q180673": GEOGRAPHY,   # ceremonial county of England
    "Q3502482": GEOGRAPHY,  # cultural region
    "Q1620908": GEOGRAPHY,  # historical region (a place)
    "Q15239622": GEOGRAPHY, # disputed territory
    "Q34918903": GEOGRAPHY, # National Park of the United States
    "Q186516": GEOGRAPHY,   # national flag
    # history (periods / conflicts / dynasties / cultures / mythology / religion)
    "Q11514315": HISTORY,   # historical period
    "Q124734": HISTORY,     # rebellion
    "Q350604": HISTORY,     # armed conflict
    "Q164950": HISTORY,     # dynasty
    "Q465299": HISTORY,     # archaeological culture
    "Q11042": HISTORY,      # culture
    "Q4204501": HISTORY,    # historical ethnic group
    "Q17149090": HISTORY,   # armed organization
    "Q7278": HISTORY,       # political party
    "Q9174": HISTORY,       # religion
    # mythology & biblical (ancient world -> history)
    "Q20643955": HISTORY,   # human biblical figure
    "Q29154430": HISTORY,   # book of the Bible
    "Q179461": HISTORY,     # religious text
    "Q30149195": HISTORY,   # biblical concept
    "Q22989102": HISTORY,   # Greek deity
    "Q205985": HISTORY,     # goddess
    "Q41863069": HISTORY,   # war deity
    "Q113103481": HISTORY,  # Olympian god
    "Q22988604": HISTORY,   # mythological Greek character
    "Q4271324": HISTORY,    # mythical character
    "Q13002315": HISTORY,   # legendary figure
    # science (anatomy / medicine / math / physics / chemistry / astronomy / CS / biology)
    "Q112826905": SCIENCE,  # class of anatomical entity
    "Q103812529": SCIENCE,  # organ type
    "Q5058355": SCIENCE,    # cellular component
    "Q112965645": SCIENCE,  # symptom or sign
    "Q24034552": SCIENCE,   # mathematical concept
    "Q214070": SCIENCE,     # physical law
    "Q17444909": SCIENCE,   # astronomical object type
    "Q59199015": SCIENCE,   # group of stereoisomers (drug/chemistry)
    "Q9143": SCIENCE,       # programming language
    "Q12772052": SCIENCE,   # multi-paradigm programming language
    "Q3239681": SCIENCE,    # scientific theory
    "Q67206691": SCIENCE,   # infrared source (astronomy)
    "Q39367": SCIENCE,      # dog breed (zoology)
    "Q82047057": SCIENCE,   # UCUM derived unit
}
# non-quizzable Wikimedia meta types -> DROP (keep=0): never good trivia subjects
DROP_INSTANCE = {
    "Q13406463",   # Wikimedia list article
    "Q4167410",    # Wikimedia disambiguation page
    "Q4167836",    # Wikimedia category
    "Q11266439",   # Wikimedia template
    "Q13406463",   # (dup, harmless)
}
# appropriateness gate — instance-of types we don't ask trivia about (mission)
BLOCK_INSTANCE = {
    "Q18127",      # record label? (keep music actually) -- (left here intentionally minimal)
}
# explicit/off-mission keyword gate on the title (light; not over-censoring history/biology)
BLOCK_TITLE_SUBSTR = ["pornhub", "xvideos", "xhamster", "onlyfans", "brazzers"]

# ---- numeric facts (closest / bigger) : prop -> (label, unit) ---------------
NUMERIC = {
    "P1082": ("population", ""), "P2046": ("area", "km2"), "P2044": ("elevation", "m"),
    "P2048": ("height", "m"), "P2386": ("diameter", "m"), "P1083": ("capacity", ""),
    "P2067": ("mass", "kg"), "P2043": ("length", "m"), "P1086": ("atomic_number", ""),
}
# ---- date facts (ordering / which-first) : prop -> label --------------------
DATES = {
    "P569": "birth", "P570": "death", "P571": "inception", "P577": "publication",
    "P580": "start", "P585": "point_in_time", "P575": "discovery",
}
# ---- 1:1 relations (matching) : prop -> label ------------------------------
RELATIONS = {
    "P36": "capital", "P50": "author", "P57": "director", "P86": "composer",
    "P17": "country", "P176": "manufacturer", "P112": "founder", "P61": "discoverer",
    "P175": "performer", "P170": "creator", "P30": "continent", "P38": "currency",
    "P37": "official_language",
}

_last = [0.0]
def _throttle(mi=0.12):
    w = mi - (time.monotonic() - _last[0])
    if w > 0: time.sleep(w)
    _last[0] = time.monotonic()

def wd(qids, retries=6):
    params = {"action": "wbgetentities", "ids": "|".join(qids), "format": "json",
              "props": "labels|aliases|claims|sitelinks/urls",
              "languages": "en", "sitefilter": "enwiki", "maxlag": "5"}
    url = WD + "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        _throttle()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return json.load(urllib.request.urlopen(req, timeout=50))
        except Exception:
            if attempt == retries - 1: raise
            time.sleep(2 ** attempt)

def _mainsnak_qid(claim):
    dv = claim.get("mainsnak", {}).get("datavalue", {})
    if dv.get("type") == "wikibase-entityid":
        return dv["value"].get("id")
    return None

def _mainsnak_quantity(claim):
    dv = claim.get("mainsnak", {}).get("datavalue", {})
    if dv.get("type") == "quantity":
        try: return float(dv["value"]["amount"])
        except Exception: return None
    return None

def _mainsnak_image(claim):
    dv = claim.get("mainsnak", {}).get("datavalue", {})
    if dv.get("type") == "string":
        fn = dv.get("value", "")
        if fn:
            return "https://commons.wikimedia.org/wiki/Special:FilePath/" + \
                   urllib.parse.quote(fn.replace(" ", "_")) + "?width=800"
    return None

def _mainsnak_time(claim):
    dv = claim.get("mainsnak", {}).get("datavalue", {})
    if dv.get("type") == "time":
        t = dv["value"].get("time", "")  # like +1879-03-14T00:00:00Z
        m = t[1:5] if len(t) >= 5 and (t[0] in "+-") else None
        try: return int(t[1:5]) if t[0] == "+" else -int(t[1:5])
        except Exception: return None
    return None

def categorize(p31, p106):
    if "Q5" in p31:                       # human → occupation
        for q in p106:
            if q in OCCUPATION: return OCCUPATION[q]
    for q in p31:
        if q in INSTANCE: return INSTANCE[q]
    # Unmapped human / non-human → 'mixed' (a real app category). Don't force
    # humans to history — that buried businesspeople / activists / presenters in
    # the wrong domain.
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    for col, ddl in [("sitelinks", "INTEGER"), ("keep", "INTEGER DEFAULT 1"),
                     ("p31", "TEXT"), ("p106", "TEXT"), ("image", "TEXT"), ("aliases", "TEXT")]:
        if not _has_col(con, "subject", col):
            con.execute(f"ALTER TABLE subject ADD COLUMN {col} {ddl}")
    con.execute("CREATE TABLE IF NOT EXISTS fact (qid TEXT, prop TEXT, label TEXT, value REAL, unit TEXT, kind TEXT)")
    con.execute("CREATE TABLE IF NOT EXISTS relation (qid TEXT, prop TEXT, label TEXT, target_qid TEXT)")
    con.execute("DELETE FROM fact"); con.execute("DELETE FROM relation")
    con.commit()

    rows = con.execute("SELECT qid, title FROM subject ORDER BY qrank DESC").fetchall()
    if args.limit: rows = rows[:args.limit]
    qids = [r[0] for r in rows]
    title_of = {r[0]: r[1] for r in rows}

    cats, kept, dropped, facts, rels = {}, 0, 0, 0, 0
    for i in range(0, len(qids), 50):
        batch = qids[i:i+50]
        ent = wd(batch).get("entities", {})
        for qid in batch:
            e = ent.get(qid, {})
            claims = e.get("claims", {})
            title = title_of[qid]
            # appropriateness gate
            keep = 1
            if any(s in title.lower() for s in BLOCK_TITLE_SUBSTR): keep = 0
            p31 = [q for q in (_mainsnak_qid(c) for c in claims.get("P31", [])) if q]
            p106 = [q for q in (_mainsnak_qid(c) for c in claims.get("P106", [])) if q]
            cat = categorize(p31, p106)
            sitelinks = len(e.get("sitelinks", {})) if e.get("sitelinks") else 0
            # aliases (en) + P18 image — fed to Type-the-answer (Q6) and Picture ID (Q7)
            aliases = [a.get("value") for a in e.get("aliases", {}).get("en", []) if a.get("value")]
            image = None
            for c in claims.get("P18", [])[:1]:
                image = _mainsnak_image(c)
            con.execute("UPDATE subject SET category=?, sitelinks=?, keep=?, p31=?, p106=?, image=?, aliases=? WHERE qid=?",
                        (cat, sitelinks, keep, ",".join(p31[:6]), ",".join(p106[:6]),
                         image, json.dumps(aliases[:12], ensure_ascii=False), qid))
            cats[cat or "mixed"] = cats.get(cat or "mixed", 0) + 1
            kept += keep; dropped += (1 - keep)
            # facts: numeric
            for p, (lbl, unit) in NUMERIC.items():
                for c in claims.get(p, [])[:1]:
                    v = _mainsnak_quantity(c)
                    if v is not None:
                        con.execute("INSERT INTO fact VALUES (?,?,?,?,?,?)", (qid, p, lbl, v, unit, "num")); facts += 1
            # facts: dates (store year as value)
            for p, lbl in DATES.items():
                for c in claims.get(p, [])[:1]:
                    y = _mainsnak_time(c)
                    if y is not None:
                        con.execute("INSERT INTO fact VALUES (?,?,?,?,?,?)", (qid, p, lbl, float(y), "year", "date")); facts += 1
            # relations: 1:1 (store target qid; labels resolved in a later pass)
            for p, lbl in RELATIONS.items():
                for c in claims.get(p, [])[:1]:
                    tq = _mainsnak_qid(c)
                    if tq:
                        # 5 cols: target_label is NULL here, filled by resolve_relations.py.
                        con.execute("INSERT INTO relation VALUES (?,?,?,?,?)", (qid, p, lbl, tq, None)); rels += 1
        con.commit()
        if (i // 50) % 10 == 0:
            print(f"  …enriched {min(i+50, len(qids))}/{len(qids)}")

    con.commit()
    print("\n=== STAGE B (enrichment) ===")
    print(f"  subjects enriched: {len(qids):,}")
    print(f"  kept / dropped (appropriateness): {kept:,} / {dropped}")
    print(f"  facts: {facts:,}   relations: {rels:,}")
    print(f"  category distribution: {dict(sorted(cats.items(), key=lambda x:-x[1]))}")
    uncat = cats.get('mixed', 0)
    print(f"  uncategorized: {uncat:,} ({100*uncat//max(1,len(qids))}%)")
    con.close()


def _has_col(con, table, col):
    return any(r[1] == col for r in con.execute(f"PRAGMA table_info({table})").fetchall())


if __name__ == "__main__":
    main()
