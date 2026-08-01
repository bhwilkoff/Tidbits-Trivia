// Tidbits — data layer (web). Corpus loader (bundled JSON, cached in
// IndexedDB) + Wikipedia client (live generation). Mirrors the Apple
// CorpusDatabase + WikipediaClient. All network goes through here.

import { makeQuestions, stableSeed, seededRng, shuffle, pickDaily } from './engine.js';

const ACTION = 'https://en.wikipedia.org/w/api.php';
const COLS = ['id', 'prompt', 'options', 'correctIndex', 'categoryID', 'difficulty', 'explanation', 'sourceTitle', 'sourceURL'];

function rowToQuestion(r) {
  const q = {};
  COLS.forEach((c, i) => (q[c] = r[i]));
  // Mirrors JSONQuestionSource.swift: the id's first colon segment identifies
  // the generation template (src/rel/wd/... for corpus+picture rows, or the
  // game-type prefix — match/order/odd/... — for the other shaped types).
  q.templateID = (r[0] || '').split(':')[0] || 'json';
  // 10th element is type-disambiguated: a string is Picture ID's Commons image
  // URL, an array is the corpus's Wikipedia-category tags — the two shapes
  // never coexist in the same file, so one index serves both.
  if (typeof r[9] === 'string' && r[9]) q.image = r[9];
  if (Array.isArray(r[9])) q.tags = r[9];
  return q;
}

// --- IndexedDB tiny KV (cache the corpus blob) ---
const DB_NAME = 'tidbits', STORE = 'kv';
function idb() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE);
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
async function idbGet(key) {
  // Race a timeout so a hung IndexedDB never blocks the corpus load
  // (the fetch path is the source of truth; IDB is only a cache).
  const timeout = new Promise((res) => setTimeout(() => res(undefined), 1500));
  const read = (async () => {
    try {
      const db = await idb();
      return await new Promise((res) => {
        const t = db.transaction(STORE).objectStore(STORE).get(key);
        t.onsuccess = () => res(t.result);
        t.onerror = () => res(undefined);
      });
    } catch { return undefined; }
  })();
  return Promise.race([read, timeout]);
}
async function idbSet(key, val) {
  try {
    const db = await idb();
    db.transaction(STORE, 'readwrite').objectStore(STORE).put(val, key);
  } catch { /* best-effort cache */ }
}

// Lowercase + strip diacritics, so "beyonce" finds "Beyoncé". Mirrors the corpus
// build's sparse search_text column and the Swift/Kotlin/C# `fold` — all must agree
// or the same topic returns different questions per platform.
const _foldCache = new Map();
function fold(s) {
  if (!s) return '';
  // Fast path: a pure-ASCII string folds to its lowercase form, so the ~91% of rows
  // with no diacritics never pay for NFKD and never enter the cache. That matters —
  // caching every corpus string would hold a second copy of the whole 54MB corpus in
  // memory, which is the exact failure mode that got Android rejected once.
  if (!/[^\x00-\x7F]/.test(s)) return s.toLowerCase();
  let f = _foldCache.get(s);
  if (f === undefined) {
    f = s.normalize('NFKD').replace(/\p{M}+/gu, '').toLowerCase();
    _foldCache.set(s, f);
  }
  return f;
}

// Round-robin a scored, already-ranked list across categories, capping how many
// come from any one domain — the anti-monopoly rule for Create (owner: too many
// sports/geography questions when a topic is dense in one category).

const STOPWORDS = new Set(['the', 'and', 'for', 'with', 'from', 'that', 'this', 'his', 'her', 'its', 'was', 'were', 'are', 'who', 'what', 'which', 'how', 'why', 'all', 'any']);

const isWordChar = (c) => /[\p{L}\p{N}]/u.test(c);

// Word-bounded containment — the single most load-bearing rule in Create. Plain
// `includes` matched the typed word INSIDE longer words, so "Ansel Adams" returned
// Hansel and Gretel, "Harry Kane" returned Spokane, "India" returned Indianapolis.
// Mirrors Swift `containsWord`.
function containsWord(text, token) {
  if (!token) return false;
  let from = 0;
  for (;;) {
    const i = text.indexOf(token, from);
    if (i < 0) return false;
    const end = i + token.length;
    const beforeOk = i === 0 || !isWordChar(text[i - 1]);
    const afterOk = end === text.length || !isWordChar(text[end]);
    if (beforeOk && afterOk) return true;
    from = i + 1;
  }
}

// Does `token` occur in the prompt as ITSELF, rather than as part of someone else's
// name? Word-bounded matching is not enough inside prose: "Denver" matched "...and
// John Denver", "Michael Jackson" matched a Glenda Jackson biopic. The tell is the
// word before it — Capitalized and not itself part of the typed topic means a
// different proper name. That second half keeps "John Lennon and Paul McCartney"
// matching for "Paul McCartney". A possessive is still the name ("Jackson's").
function promptHasWord(raw, token, topic) {
  const bareOf = (w) => {
    let b = [...String(w)].filter((c) => /[\p{L}\p{N}'’]/u.test(c)).join('');
    for (const suffix of ["'s", '\u2019s']) if (b.endsWith(suffix)) b = b.slice(0, -suffix.length);
    return fold([...b].filter((c) => /[\p{L}\p{N}]/u.test(c)).join(''));
  };
  const words = String(raw || '').split(/[ \n\t]+/).filter(Boolean);
  let previous = null;
  for (const w of words) {
    if (bareOf(w) === token) {
      if (previous && /\p{Lu}/u.test(previous[0])
          && !topic.includes(fold([...previous].filter((c) => /[\p{L}\p{N}]/u.test(c)).join('')))) {
        previous = w;
        continue;
      }
      return true;
    }
    previous = w;
  }
  // Hyphenated or punctuated forms ("Denver-based") the split cannot see.
  return containsWord(fold(raw || ''), token) && !words.some((w) => bareOf(w) === token);
}

// A Wikipedia disambiguator is not part of what the player means:
// "Backrooms (film)", "Masters of the Universe (2026 film)".
function stripParens(s) {
  let out = '', depth = 0;
  for (const c of String(s || '')) {
    if (c === '(' || c === '[') { depth++; continue; }
    if (c === ')' || c === ']') { depth = Math.max(0, depth - 1); continue; }
    if (depth === 0) out += c;
  }
  return out.trim();
}

// Punctuation flattened to single spaces, nothing dropped — phrase matching needs
// the stopwords kept and in order ("masters of the universe"), and needs the
// parenthetical kept on ROW titles, where it carries the meaning.
function flattened(s) {
  return fold(String(s || '')).split(/[^\p{L}\p{N}]+/u).filter(Boolean).join(' ');
}

// The typed topic as a matchable phrase: disambiguator removed, order kept.
function topicPhrase(s) { return flattened(stripParens(s)); }

// Did the topic lose MEANINGFUL words to the >=3-character rule? "George VI"
// reduces to the single token `george`, so every George matched — measured, it
// returned George Martin, George Mallory, George Eliot and Paul George; "O. J.
// Simpson" reduced to `simpson` and returned Homer and Bart. A regnal numeral or
// an initial is short but not insignificant, and the tell is that the phrase still
// holds a non-stopword the token list threw away. Does NOT fire for "The Beatles",
// where the dropped word is a stopword.
function phraseIsRequired(topic) {
  const significant = topicPhrase(topic).split(' ').filter((w) => w && !STOPWORDS.has(w));
  return significant.length > topicTokens(topic).length;
}

function topicTokens(s) {
  const raw = flattened(stripParens(s)).split(' ').filter((t) => t.length >= 3);
  const kept = raw.filter((t) => !STOPWORDS.has(t));
  return kept.length ? kept : raw;
}

// Wikipedia categories mean "about" only in their agentive form. "Albums produced
// by Michael Jackson" makes a Thriller question an MJ question; "Actresses from
// Denver" does not make a Kristin Cavallari birth-year question a Denver question.
function hasAgentiveTag(tags, phrase) {
  for (const t of tags) {
    for (const prep of ['by ', 'of ']) {
      let from = 0;
      for (;;) {
        const i = t.indexOf(prep, from);
        if (i < 0) break;
        let rest = t.slice(i + prep.length);
        if (rest.startsWith('the ')) rest = rest.slice(4);
        if (rest.startsWith(phrase)) {
          const after = rest.slice(phrase.length);
          if (!after.length || !isWordChar(after[0])) return true;
        }
        from = i + prep.length;
      }
    }
  }
  return false;
}

// Relevance TIER, or null to REJECT. A floor, not just a ranking: a topic the
// corpus knows nothing about must fall through to live generation rather than
// produce eight confident strangers. Mirrors Swift `tier`.
//
//   3 the row's subject IS the topic
//   2 the whole typed phrase appears, word-bounded, in the title
//   1 every typed word appears, word-bounded, in the title
//   0 every typed word appears in the prompt the player reads
//  -1 an agentive tag only — a real connection the question never shows
//
// The OPTIONS are deliberately not consulted: that made the topic match as a
// DISTRACTOR ("Zlatan Ibrahimović" returned a picture of Neymar) because the
// giveaway rule had already removed every row where it was the right answer.
function tierOf(title, prompt, tags, tokens, phrase, guardNames, requirePhrase = false) {
  const fTitle = fold(title || '');
  const subject = flattened(title || '');
  // Identity ignores the disambiguator — "Drake (musician)" IS Drake, and the corpus
  // has no row titled plainly "Drake", so without this the guard never armed and
  // typing "Drake" returned Nick Drake, Tim Drake and Drake & Josh.
  if (subject === phrase || flattened(stripParens(title || '')) === phrase) return 3;
  if (containsWord(subject, phrase)) {
    // When the typed word is itself a subject here, a bare two-word title that
    // merely contains it is a DIFFERENT named thing: "Bob Denver".
    if (guardNames && subject.split(' ').length === 2) return null;
    return 2;
  }
  // A numeral or an initial was dropped as "too short", so the surviving tokens
  // name the wrong thing — only the phrase above could be trusted.
  if (requirePhrase) return containsWord(fold(prompt || ''), phrase) ? 0 : null;
  const need = tokens.length <= 2 ? tokens.length : tokens.length - 1;
  if (tokens.filter((t) => containsWord(fTitle, t)).length >= need) return 1;
  if (tokens.filter((t) => containsWord(fTitle, t) || promptHasWord(prompt || '', t, tokens)).length >= need) return 0;
  // An agentive tag is a real connection but an INVISIBLE one: the question never
  // says so. It was the last measurable source of drift — "Rod Stewart" produced
  // Britt Ekland's height off a "Partners of Rod Stewart" tag. The tag still scores.
  return null;
}

// Take from the highest occupied relevance tier first, diversifying INSIDE it.
// Diversifying across tiers is what promoted a one-word coincidence into a
// category lane — "Ansel Adams" returned exactly one row per category (Samuel
// Adams, Hansel and Gretel, Phil Anselmo, Davante Adams…).
function fillByTier(scored, limit) {
  const out = [];
  for (const t of [3, 2, 1, 0]) {
    if (out.length >= limit) break;
    // Score THEN id: Swift's sort is not stable, so a score-only sort let tied rows
    // come out in different orders per platform, and the per-category cap then kept
    // a different SET.
    const lane = scored.filter((x) => x[2] === t)
      .sort((a, b) => (b[1] - a[1]) || (a[0].id < b[0].id ? -1 : a[0].id > b[0].id ? 1 : 0))
      .map((x) => x[0]);
    out.push(...diversify(lane, limit - out.length));
  }
  return out.slice(0, limit);
}

function diversify(ranked, limit) {
  const perCat = Math.max(2, Math.ceil(limit / 3));   // ~1/3 of the set, min 2
  const byCat = new Map();
  for (const q of ranked) {
    const c = q.categoryID || 'mixed';
    if (!byCat.has(c)) byCat.set(c, []);
    if (byCat.get(c).length < perCat) byCat.get(c).push(q);
  }
  // Interleave categories (best-ranked first within each) until we hit the limit.
  const lanes = [...byCat.values()];
  const out = [];
  let added = true;
  while (out.length < limit && added) {
    added = false;
    for (const lane of lanes) {
      if (lane.length) { out.push(lane.shift()); added = true; if (out.length >= limit) break; }
    }
  }
  // The per-category cap is an ANTI-MONOPOLY rule, not a quota: when the
  // relevant pool is genuinely single-domain it must not starve the set
  // ("Marie Curie" is all science — capping at 3 turned a requested 8 into 4).
  if (out.length < limit) {
    const taken = new Set(out.map((q) => q.id));
    for (const q of ranked) {
      if (out.length >= limit) break;
      if (!taken.has(q.id)) { out.push(q); taken.add(q.id); }
    }
  }
  // Shuffle so the quiz doesn't march category-by-category.
  for (let i = out.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [out[i], out[j]] = [out[j], out[i]]; }
  return out;
}

export const Corpus = {
  questions: [], byCategory: {}, loaded: false,

  async load() {
    if (this.loaded) return;
    // Network-first so corpus updates always propagate; IndexedDB is only an
    // offline fallback, keyed on the corpus content version (no stale cache).
    let data;
    try {
      const resp = await fetch('assets/corpus.json', { cache: 'no-cache' });
      if (resp.ok) {
        data = await resp.json();
        idbSet('corpus:' + data.version, data);
        idbSet('corpus:latest', data.version);
      }
    } catch (e) { /* offline — fall back to cache */ }
    if (!data) {
      const v = await idbGet('corpus:latest');
      if (v) data = await idbGet('corpus:' + v);
    }
    if (!data) throw new Error('corpus unavailable');
    this.questions = data.questions.map(rowToQuestion);
    this.byCategory = {};
    for (const q of this.questions) (this.byCategory[q.categoryID] ||= []).push(q);
    this.loaded = true;
    // Observability: confirm WHICH corpus is live (open DevTools console). If
    // this version doesn't match the latest assets/corpus.json, you're on a
    // stale cache — hard-refresh to pick up the new service worker.
    this.version = data.version;
    console.log(`[Tidbits] corpus v${data.version} · ${this.questions.length} questions`);
  },

  pull(categoryID, seen, limit) {
    const src = categoryID === 'mixed' ? this.questions : (this.byCategory[categoryID] || []);
    const fresh = src.filter((q) => !seen.has(q.id));
    const a = fresh.slice();
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a.slice(0, limit);
  },

  // The canonical cross-platform Daily (Decision 037): identical 7 on
  // iOS/tvOS/Android/web via the shared hash-rank pick — see engine.js.
  daily(dayKey, count) {
    const byId = new Map(this.questions.map((q) => [q.id, q]));
    return pickDaily(this.questions.map((q) => q.id), dayKey, 'mixed', count)
      .map((id) => byId.get(id)).filter(Boolean);
  },

  // Create: real, already-vetted corpus questions matching the topic's words
  // (prompt + Wikipedia source title). Grounded generation's retrieval baseline —
  // no hallucination (docs/CREATE-QUESTION-GEN-PLAYBOOK.md).
  search(topic, limit) {
    // Stopwords are dropped, not merely short words: the >=3 rule kept "the",
    // which matches nearly every row and crowds real hits out before ranking
    // ("The Beatles", "The Simpsons"). Mirrors Swift/Kotlin/C#.
    const tokens = topicTokens(topic);
    if (!tokens.length) return [];
    // A topic made of nothing but stopwords cannot be searched for. "From (TV
    // series)" reduces to the word `from`, which matched every row containing it —
    // Notes from Underground, Spider-Man: Far From Home, From Dusk till Dawn. The
    // corpus says so and live generation takes the topic instead.
    if (!tokens.some((t) => !STOPWORDS.has(t))) return [];
    const phrase = topicPhrase(topic);
    // Is the typed word itself a subject here? That single fact is what licenses
    // the different-person guard: "Denver" is a place in this corpus, so "Bob
    // Denver" is someone else. "Potter" is not, so "Harry Potter" is the best
    // reading of it.
    const guardNames = tokens.length === 1
      && this.questions.some((q) => flattened(q.sourceTitle) === phrase
        || flattened(stripParens(q.sourceTitle || '')) === phrase);
    const requirePhrase = phraseIsRequired(topic);
    const scored = [];
    const giveaways = [];
    for (const q of this.questions) {
      // Diversity (owner): drop the "which continent is X on" template — easy,
      // repetitive, and doesn't teach anything — and the trivially-easy tier.
      if ((q.id || '').startsWith('src:continent:')) continue;
      if ((q.difficulty || 2) <= 1) continue;
      // Folded, not merely lowercased: the tokens are folded, so an accented row
      // would score 0 against them and be dropped by the `s > 0` gate.
      // The relevance FLOOR, applied before any ranking.
      const matched = tierOf(q.sourceTitle, q.prompt, q.tags, tokens, phrase, guardNames, requirePhrase);
      if (matched === null) continue;
      const title = fold(q.sourceTitle), prompt = fold(q.prompt), explanation = fold(q.explanation);
      const tags = (q.tags || []).map(fold);
      let s = 0;
      for (const t of tokens) {
        if (tags.some((tg) => containsWord(tg, t))) s += 3;
        if (containsWord(title, t)) s += 2;
        if (containsWord(prompt, t)) s += 1;
        if (containsWord(explanation, t)) s += 1;
      }
      // How many of the typed words this row matched AT ALL. Scoring alone was
      // not enough: `diversify` round-robins by CATEGORY afterwards, so a
      // one-word coincidence got PROMOTED to fill a lane. Measured on the
      // shipping corpus, "Marie Curie" has 15 real two-word matches (all
      // science) against 211 one-word hits across 7 categories, 189 of which
      // never mention Curie — the generated quiz led with Marie de' Medici.

      // A question whose ANSWER is/contains the topic is a giveaway ("Chicago" →
      // answer "Chicago") and is held in RESERVE, not dropped: for a person most
      // good questions answer with their name (17 of the 20 real van Gogh
      // questions do), so a hard drop starved the pool below a full quiz.
      const answer = fold((q.options && q.options[q.correctIndex]) || '');
      if (tokens.some((t) => containsWord(answer, t))) giveaways.push([q, s, matched]);
      else scored.push([q, s, matched]);
    }
    // Cap per-category so a topic dense in one domain (a city with sports teams
    // → 8 sports-player questions) can't monopolize the set; round-robin across
    // categories for a genuinely varied quiz.
    const out = fillByTier(scored, limit);
    if (out.length < limit) {
      const taken = new Set(out.map((q) => q.id));
      out.push(...fillByTier(giveaways, limit).filter((q) => !taken.has(q.id)).slice(0, limit - out.length));
    }
    return out;
  },

  // Look up by ID — a saved quiz's refs resolve through here.
  question(id) {
    if (!this._byID) this._byID = new Map(this.questions.map((q) => [q.id, q]));
    return this._byID.get(id) || null;
  },

  get count() { return this.questions.length; },
};

// Enrichment-built mode sources (E1): a bundled JSON question set, same row
// shape as the corpus (Picture ID also carries a 10th element, the image URL).
// One factory so each new mode is a one-liner.
// Closest Call (M5) numeric row: [id, prompt, answer, min, max, step, tol, unit,
// category, explanation, title, url] -> a question carrying a `closest` spec.
function rowToClosest(r) {
  return {
    id: r[0], prompt: r[1], options: [], correctIndex: 0, templateID: 'closest',
    closest: { answer: r[2], min: r[3], max: r[4], step: r[5], tolerance: r[6], unit: r[7] },
    categoryID: r[8], difficulty: 3, explanation: r[9], sourceTitle: r[10], sourceURL: r[11],
  };
}

// Ordering (Q4) row: [id, prompt, names(correct order), years, cat, expl, title, url].
function rowToOrder(r) {
  return {
    id: r[0], prompt: r[1], options: r[2], correctIndex: 0, templateID: 'order',
    ordering: r[2], categoryID: r[4], difficulty: 3, explanation: r[5], sourceTitle: r[6], sourceURL: r[7],
  };
}

// Type-the-answer (Q6) row: [id, prompt, answer, accepted(list), cat, expl, title, url].
function rowToType(r) {
  return {
    id: r[0], prompt: r[1], options: [r[2]], correctIndex: 0, templateID: 'type',
    accepted: r[3], categoryID: r[4], difficulty: 3, explanation: r[5], sourceTitle: r[6], sourceURL: r[7],
  };
}

// Matching (Q5) row: [id, prompt, keys, values(correct, parallel), cat, expl, "", ""].
function rowToMatch(r) {
  return {
    id: r[0], prompt: r[1], options: r[2], correctIndex: 0, templateID: 'match',
    matching: { keys: r[2], values: r[3] }, categoryID: r[4], difficulty: 3, explanation: r[5], sourceTitle: '', sourceURL: '',
  };
}

// Enumeration (Q8) row: [id, prompt, groups([[canonical, alias...]]), cat, seconds, url].
function rowToEnum(r) {
  return {
    id: r[0], prompt: r[1], options: [], correctIndex: 0, templateID: 'enum',
    enumerate: { groups: r[2] }, categoryID: r[3], difficulty: 3, explanation: '', sourceTitle: '', sourceURL: r[5] || '',
  };
}

function makeJsonSet(filename, parseRow = rowToQuestion) {
  return {
    questions: [], byCategory: {}, loaded: false,
    async load() {
      if (this.loaded) return;
      try {
        const resp = await fetch('assets/' + filename, { cache: 'no-cache' });
        if (!resp.ok) return;
        const data = await resp.json();
        this.questions = data.questions.map(parseRow);
        this.byCategory = {};
        for (const q of this.questions) (this.byCategory[q.categoryID] ||= []).push(q);
        this.loaded = true;
        console.log(`[Tidbits] ${filename} v${data.version} · ${this.questions.length} questions`);
      } catch (e) { console.warn('[Tidbits]', filename, 'unavailable', e); }
    },
    // Look up by ID — what a saved quiz needs to turn its set-refs back into
    // questions (docs/QUIZ-CONTRACT.md). Built on first use; these sets are small.
    question(id) {
      if (!this._byID) this._byID = new Map(this.questions.map((q) => [q.id, q]));
      return this._byID.get(id) || null;
    },
    pull(categoryID, seen, limit) {
      const src = categoryID === 'mixed' ? this.questions : (this.byCategory[categoryID] || []);
      const a = src.filter((q) => !seen.has(q.id)).slice();
      for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
      return a.slice(0, limit);
    },
    // Topic-matched pull (Create shape variety): questions whose prompt/title
    // mention a topic token, answer doesn't give it away.
    async searchMatch(topic, limit) {
      await this.load();
      const tokens = topic.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length >= 3);
      if (!tokens.length) return [];
      const hits = this.questions.filter((q) => {
        const ans = ((q.options && q.options[q.correctIndex]) || '').toLowerCase();
        if (tokens.some((t) => ans.includes(t))) return false;
        const hay = `${q.prompt} ${q.sourceTitle} ${q.explanation || ''} ${(q.tags || []).join(' ')}`.toLowerCase();
        return tokens.some((t) => hay.includes(t));
      });
      for (let i = hits.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [hits[i], hits[j]] = [hits[j], hits[i]]; }
      return hits.slice(0, limit);
    },
  };
}
export const Pictures = makeJsonSet('picture.json');
export const ThisOrThat = makeJsonSet('thisorthat.json');
export const ClosestCall = makeJsonSet('closest.json', rowToClosest);
export const Ordering = makeJsonSet('order.json', rowToOrder);
export const Matching = makeJsonSet('match.json', rowToMatch);
export const TypeAnswer = makeJsonSet('typeanswer.json', rowToType);
export const OddOneOut = makeJsonSet('oddoneout.json');   // standard MCQ rows
export const Enumerate = makeJsonSet('enumerate.json', rowToEnum);   // Q8 list puzzles

// F3 derived-difficulty overlay (Wikipedia pageviews → 1..5 per subject).
export const Difficulty = {
  map: {}, loaded: false,
  async load() {
    if (this.loaded) return;
    try { const r = await fetch('assets/difficulty.json', { cache: 'no-cache' }); if (!r.ok) return; const d = await r.json(); this.map = d.difficulty || {}; this.loaded = true; } catch (e) { /* default 3 */ }
  },
  get(title) { return this.map[(title || '').replace(/ /g, '_')] ?? 3; },
};

// The Daily's global board — the $0 layer that ranks everyone who played today's Daily
// (docs/DAILY-BOARD-CONTRACT.md). The Daily set is the shared pickDaily; results come from
// the static JSON the hourly cron commits to data/dailyboard/ — free/cacheable, never a
// live RTDB read. This is a LAYER on the Daily, not a separate mode.
export const DailyBoard = {
  // The published board for a day, or null if the cron hasn't published it yet
  // (e.g. nobody has played today, or it's the current in-progress day).
  async results(dayKey) {
    try {
      const r = await fetch(`data/dailyboard/${dayKey}.json`, { cache: 'no-cache' });
      return r.ok ? await r.json() : null;
    } catch { return null; }
  },

  // Your percentile from the published histogram: the share of players you strictly
  // beat. Pure + tiny, so a player outside the top board still sees "you beat 83%".
  // Returns null when the histogram is empty (you'd be the only/first player).
  percentile(hist, myScore) {
    if (!hist) return null;
    let below = 0, total = 0;
    for (const [score, count] of Object.entries(hist)) {
      total += count;
      if (Number(score) < myScore) below += count;
    }
    return total ? Math.round((below / total) * 100) : null;
  },
};

// Free-text normalization (mirror of GameEngine.normalizeType).
export function normalizeType(s) {
  let t = (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  t = t.replace(/[^a-z0-9]+/g, ' ').trim();
  if (t.startsWith('the ')) t = t.slice(4);
  return t;
}
export function matchesAccepted(input, accepted) {
  const n = normalizeType(input);
  return !!n && accepted.some((a) => normalizeType(a) === n);
}

export const Wikipedia = {
  async search(topic, limit = 35) {
    const url = `${ACTION}?action=query&list=search&srsearch=${encodeURIComponent(topic)}&srlimit=${limit}&srnamespace=0&format=json&origin=*`;
    const r = await fetch(url);
    const j = await r.json();
    return (j.query?.search || []).map((h) => h.title);
  },

  async summaries(titles) {
    const out = [];
    for (let i = 0; i < titles.length; i += 50) {
      const batch = titles.slice(i, i + 50);
      const url = `${ACTION}?action=query&prop=extracts|description|info&exintro=1&explaintext=1&inprop=url&redirects=1&titles=${encodeURIComponent(batch.join('|'))}&format=json&origin=*`;
      try {
        const r = await fetch(url);
        const j = await r.json();
        for (const p of Object.values(j.query?.pages || {})) {
          if (!p.title) continue;
          out.push({ title: p.title, description: p.description, extract: p.extract, pageURL: p.fullurl, type: p.description || '' });
        }
      } catch { /* skip batch */ }
    }
    return out;
  },

  async generate(topic, categoryID, count) {
    const titles = await this.search(topic, 35);
    if (!titles.length) return [];
    const all = await this.summaries(titles);
    // Wikipedia's search returns what is RELATED to the topic, not what is about
    // it: "Zendaya" brings back Tom Holland, Law Roach and Dune. An article earns
    // its place only if it names the topic — the whole PHRASE, since requiring only
    // the words let "Albert Einstein" through Bob Einstein, whose summary happens to
    // name his brother Albert. And the same different-person guard the corpus ranker
    // uses is needed here, or "Denver" fetches John Denver straight from Wikipedia
    // after the corpus correctly refused him.
    const tokens = topicTokens(topic);
    const phrase = topicPhrase(topic);
    const guardNames = tokens.length === 1
      && all.some((s) => flattened(s.title) === phrase);
    const onTopic = all.filter((s) => {
      const subject = flattened(s.title);
      if (guardNames && subject !== phrase && subject.split(' ').length === 2
          && containsWord(subject, phrase)) return false;
      return containsWord(
        fold(`${s.title} ${s.extract || ''} ${s.description || ''}`), phrase);
    });
    return makeQuestions(onTopic, categoryID, count, stableSeed(topic), true, all);
  },
};
