// Tidbits — data layer (web). Corpus loader (bundled JSON, cached in
// IndexedDB) + Wikipedia client (live generation). Mirrors the Apple
// CorpusDatabase + WikipediaClient. All network goes through here.

import { makeQuestions, stableSeed, seededRng, shuffle, pickDaily } from './engine.js';

const ACTION = 'https://en.wikipedia.org/w/api.php';
const COLS = ['id', 'prompt', 'options', 'correctIndex', 'categoryID', 'difficulty', 'explanation', 'sourceTitle', 'sourceURL'];

function rowToQuestion(r) {
  const q = {};
  COLS.forEach((c, i) => (q[c] = r[i]));
  q.templateID = 'corpus';
  if (r[9]) q.image = r[9];   // Picture ID (Q7): 10th element = image URL
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

// Round-robin a scored, already-ranked list across categories, capping how many
// come from any one domain — the anti-monopoly rule for Create (owner: too many
// sports/geography questions when a topic is dense in one category).
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
    const tokens = topic.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length >= 3);
    if (!tokens.length) return [];
    const scored = [];
    for (const q of this.questions) {
      // Drop questions whose ANSWER is/contains the topic — the player typed it,
      // so that's a giveaway ("Chicago" → answer "Chicago"). Keep ones ABOUT it.
      const answer = ((q.options && q.options[q.correctIndex]) || '').toLowerCase();
      if (tokens.some((t) => answer.includes(t))) continue;
      // Diversity (owner): drop the "which continent is X on" template — easy,
      // repetitive, and doesn't teach anything — and the trivially-easy tier.
      if ((q.id || '').startsWith('src:continent:')) continue;
      if ((q.difficulty || 2) <= 1) continue;
      const title = (q.sourceTitle || '').toLowerCase(), prompt = (q.prompt || '').toLowerCase(), explanation = (q.explanation || '').toLowerCase();
      let s = 0;
      for (const t of tokens) { if (title.includes(t)) s += 2; if (prompt.includes(t)) s += 1; if (explanation.includes(t)) s += 1; }
      if (s > 0) scored.push([q, s]);
    }
    scored.sort((a, b) => b[1] - a[1]);
    // Cap per-category so a topic dense in one domain (a city with sports teams
    // → 8 sports-player questions) can't monopolize the set; round-robin across
    // categories for a genuinely varied quiz.
    return diversify(scored.map((x) => x[0]), limit);
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
        const hay = `${q.prompt} ${q.sourceTitle} ${q.explanation || ''}`.toLowerCase();
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
    const sums = await this.summaries(titles);
    return makeQuestions(sums, categoryID, count, stableSeed(topic));
  },
};
