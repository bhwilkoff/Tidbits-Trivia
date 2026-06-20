// Tidbits — data layer (web). Corpus loader (bundled JSON, cached in
// IndexedDB) + Wikipedia client (live generation). Mirrors the Apple
// CorpusDatabase + WikipediaClient. All network goes through here.

import { makeQuestions, stableSeed, seededRng, shuffle } from './engine.js';

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

  // Deterministic daily slice (same for everyone on a given day).
  daily(dayKey, count) {
    const rnd = seededRng(stableSeed(dayKey));
    return shuffle(this.questions, rnd).slice(0, count);
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
  };
}
export const Pictures = makeJsonSet('picture.json');
export const ThisOrThat = makeJsonSet('thisorthat.json');
export const ClosestCall = makeJsonSet('closest.json', rowToClosest);

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
