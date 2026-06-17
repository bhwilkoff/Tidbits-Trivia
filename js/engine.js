// Tidbits — question engine (JS mirror of Core/Engine in the Apple app).
// Same template shapes + quality gates so web and native produce identical
// questions. Keep in lockstep with TemplateEngine.swift (Decision 019).

// --- Deterministic RNG (splitmix64-ish, 32-bit safe via BigInt) ---
export function seededRng(seed) {
  let state = BigInt.asUintN(64, BigInt(seed) + 0x9e3779b97f4a7c15n);
  return function next() {
    state = BigInt.asUintN(64, state + 0x9e3779b97f4a7c15n);
    let z = state;
    z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
    z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94d049bb133111ebn);
    z = z ^ (z >> 31n);
    return Number(z % 1000000n) / 1000000; // [0,1)
  };
}

export function stableSeed(str) {
  // FNV-1a 32-bit (enough for seeding here).
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function shuffle(arr, rnd) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// --- Scoring (mirror Scoring.swift) ---
export const Scoring = {
  base: 100, maxSpeedBonus: 100, streakStep: 0.1, maxStreakMultiplier: 2.0,
  points(correct, secondsTaken, budget, streak) {
    if (!correct) return 0;
    const speedFraction = Math.max(0, Math.min(1, 1 - secondsTaken / Math.max(budget, 0.001)));
    const speed = Math.floor(this.maxSpeedBonus * speedFraction);
    const mult = Math.min(this.maxStreakMultiplier, 1 + Math.max(0, streak - 1) * this.streakStep);
    return Math.floor((this.base + speed) * mult);
  },
};

// --- Template engine for live Wikipedia generation ---
const isUsable = (s) => {
  if (s.type === 'disambiguation') return false;
  const d = s.description, e = s.extract;
  if (!d || d.length < 6 || d.length > 90) return false;
  if (!e || e.length < 40) return false;
  const lt = (s.title || '').toLowerCase();
  if (lt.startsWith('list of') || lt.includes('(disambiguation)')) return false;
  if ((e || '').toLowerCase().includes('may refer to')) return false;
  return true;
};

const stripParens = (t) => t.replace(/\s*\([^)]*\)/g, '');
const firstSentence = (t) => {
  const s = (t || '').trim();
  const m = s.match(/\.\s/);
  return m ? s.slice(0, m.index) + '.' : s;
};
const cap = (c) => (c ? c[0].toUpperCase() + c.slice(1) : c);

function redact(text, title) {
  let out = text;
  for (const needle of new Set([title, stripParens(title)])) {
    if (needle) out = out.replace(new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), '—————');
  }
  return out;
}

function pickDistractors(subject, pool, valueFn, exclude, rnd) {
  const subjWords = new Set((subject.description || '').toLowerCase().split(' '));
  const seen = new Set();
  const ranked = pool
    .filter((c) => c.title !== subject.title)
    .map((c) => {
      const v = (valueFn(c) || '').trim();
      if (!v || v.toLowerCase() === exclude.toLowerCase()) return null;
      const words = new Set((c.description || '').toLowerCase().split(' '));
      let overlap = 0; subjWords.forEach((w) => { if (words.has(w)) overlap++; });
      return { v, overlap };
    })
    .filter(Boolean)
    .sort((a, b) => b.overlap - a.overlap)
    .filter((x) => { const k = x.v.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; })
    .map((x) => x.v);
  return shuffle(ranked.slice(0, 8), rnd).slice(0, 3);
}

function difficulty(s) {
  const n = (s.extract || '').length;
  return n >= 600 ? 2 : n >= 300 ? 3 : 4;
}

function assemble(s, categoryID, prompt, correct, distractors, templateID, rnd) {
  const options = shuffle([correct, ...distractors], rnd);
  return {
    id: `live:${templateID}:${s.title}`.replace(/ /g, '_'),
    prompt,
    options,
    correctIndex: options.indexOf(correct),
    categoryID,
    difficulty: difficulty(s),
    explanation: firstSentence(s.extract || s.description || ''),
    sourceTitle: s.title,
    sourceURL: s.pageURL || null,
    templateID,
  };
}

export function makeQuestions(pool, categoryID, count, seed) {
  const usable = pool.filter(isUsable);
  if (usable.length < 4) return [];
  const rnd = seededRng(seed);
  const subjects = shuffle(usable, rnd);
  const out = [];
  for (const s of subjects) {
    if (out.length >= count) break;
    const useDesc = out.length % 2 === 0;
    let q = null;
    if (useDesc) {
      if (!s.description) continue;
      const ds = pickDistractors(s, usable, (c) => c.description, s.description, rnd);
      if (ds.length === 3) q = assemble(s, categoryID, `How is ${stripParens(s.title)} best described?`, cap(s.description), ds.map(cap), 'descriptionOf', rnd);
    } else {
      const clue = redact(firstSentence(s.extract || s.description), s.title);
      if (clue.length < 25) continue;
      const ds = pickDistractors(s, usable, (c) => c.title, s.title, rnd);
      if (ds.length === 3) q = assemble(s, categoryID, `Which subject is this? “${clue}”`, stripParens(s.title), ds.map(stripParens), 'subjectFrom', rnd);
    }
    if (q) out.push(q);
  }
  return out;
}
