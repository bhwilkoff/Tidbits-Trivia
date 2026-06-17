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

// Strip parenthetical clutter (foreign scripts, pronunciations, empty parens,
// leading ALL-CAPS acronyms that leak the answer). Fixpoint for nesting.
const LANG_RE = /\b(romaniz|pronounc|IPA|listen|lit\.|Russian|Greek|Latin|Arabic|Chinese|Japanese|Hebrew|Hindi|Persian|German|French|Spanish|Italian|Korean|Portuguese|Turkish|Polish|Dutch|Sanskrit)\b/i;
function dropParen(inner) {
  const t = inner.trim();
  if (!t) return true;
  if (/[^\x00-\x7F]/.test(t)) return true;
  if (LANG_RE.test(t)) return true;
  const tok = ((t.split(';')[0].split(/\s+/)[0]) || '').replace(/[^A-Za-z]/g, '');
  if (tok.length >= 2 && tok.length <= 6 && tok === tok.toUpperCase()) return true;
  return false;
}
function cleanClue(text) {
  let out = text, prev = null;
  while (out !== prev) {
    prev = out;
    out = out.replace(/\s*\(([^()]*)\)/g, (m, inner) => (dropParen(inner) ? '' : m));
    out = out.replace(/\s*\[([^\[\]]*)\]/g, (m, inner) => (dropParen(inner) ? '' : m));
  }
  return out.replace(/\s{2,}/g, ' ').replace(' ,', ',').replace(' .', '.').trim();
}

function redact(text, title) {
  let out = text;
  for (const needle of new Set([title, stripParens(title)])) {
    if (needle) out = out.replace(new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), '—————');
  }
  return out;
}

// Siblings ranked by description word-overlap (same-domain → plausible).
// lengthMatch (when set) prefers similar-length values to kill the
// "longest option is the answer" tell.
function rankedSiblings(subject, pool, valueFn, exclude, lengthMatch) {
  const subjWords = new Set((subject.description || '').toLowerCase().split(' '));
  const seen = new Set();
  return pool
    .filter((c) => c.title !== subject.title)
    .map((c) => {
      const v = (valueFn(c) || '').trim();
      if (!v || v.toLowerCase() === (exclude || '').toLowerCase()) return null;
      const words = new Set((c.description || '').toLowerCase().split(' '));
      let overlap = 0; subjWords.forEach((w) => { if (words.has(w)) overlap++; });
      const lenPen = lengthMatch != null ? -Math.abs(v.length - lengthMatch) : 0;
      return { v, overlap, lenPen };
    })
    .filter(Boolean)
    .sort((a, b) => (b.overlap - a.overlap) || (b.lenPen - a.lenPen))
    .filter((x) => { const k = x.v.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; })
    .map((x) => x.v);
}
const titleDistractors = (s, pool, rnd) => shuffle(rankedSiblings(s, pool, (c) => stripParens(c.title), stripParens(s.title), null).slice(0, 8), rnd).slice(0, 3);
const descDistractors = (s, pool, rnd) => shuffle(rankedSiblings(s, pool, (c) => c.description, s.description, (s.description || '').length).slice(0, 8), rnd).slice(0, 3);

function difficulty(s) {
  const n = (s.extract || '').length;
  return n >= 600 ? 2 : n >= 300 ? 3 : 4;
}

// Rotating stems (%s = clue/title); categorize is a capped minority.
const STEMS = {
  identify: ['Which subject does this describe? “%s”', 'Name it — “%s”', 'What is being described here? “%s”', 'Identify the subject: “%s”', 'These clues point to one thing. What is it? “%s”', 'Guess the article: “%s”'],
  jeopardy: ['%s — what is it?', '%s Name the subject.', '%s What are we describing?'],
  cloze: ['Fill in the blank: “%s”', 'Complete the sentence: “%s”', 'Which name completes this? “%s”'],
  categorize: ['What kind of thing is %s?', 'What is %s best known as?', 'In a few words, what is %s?', 'Which description fits %s?'],
  oneliner: ['Which one is “%s”?', '“%s” — which subject is that?', 'Which subject matches: “%s”?'],
};
const SHAPE_ROTATION = ['identify', 'jeopardy', 'cloze', 'identify', 'oneliner', 'jeopardy', 'categorize', 'cloze', 'identify', 'jeopardy'];

function buildShape(shape, s, pool, stem, rnd) {
  const fmt = (v) => stem.replace('%s', v);
  if (shape === 'identify') {
    const clue = redact(cleanClue(firstSentence(s.extract || s.description)), s.title);
    if (clue.length < 25) return null;
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    const ans = stripParens(s.title); return { prompt: fmt(clue), options: [ans, ...ds], answer: ans };
  }
  if (shape === 'jeopardy') {
    const sent = cleanClue(firstSentence(s.extract || '')); if (sent.length < 25) return null;
    const bare = stripParens(s.title); let clue;
    if (sent.toLowerCase().startsWith(s.title.toLowerCase())) clue = 'This' + sent.slice(s.title.length);
    else if (sent.toLowerCase().startsWith(bare.toLowerCase())) clue = 'This' + sent.slice(bare.length);
    else clue = redact(sent, s.title);
    clue = cap(clue.trim());
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    return { prompt: fmt(clue), options: [bare, ...ds], answer: bare };
  }
  if (shape === 'cloze') {
    const sent = cleanClue(firstSentence(s.extract || '')); const bare = stripParens(s.title); let clozed = null;
    for (const needle of [s.title, bare]) {
      if (needle && sent.toLowerCase().includes(needle.toLowerCase())) {
        clozed = sent.replace(new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), '_____'); break;
      }
    }
    if (!clozed || clozed.length < 25) return null;
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    return { prompt: fmt(clozed), options: [bare, ...ds], answer: bare };
  }
  if (shape === 'categorize') {
    if (!s.description) return null;
    const ds = descDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    const ans = cap(s.description); return { prompt: fmt(stripParens(s.title)), options: [ans, ...ds.map(cap)], answer: ans };
  }
  if (shape === 'oneliner') {
    if (!s.description) return null;
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    const ans = stripParens(s.title); return { prompt: fmt(cap(s.description)), options: [ans, ...ds], answer: ans };
  }
  return null;
}

export function makeQuestions(pool, categoryID, count, seed) {
  const usable = pool.filter(isUsable);
  if (usable.length < 4) return [];
  const rnd = seededRng(seed);
  const subjects = shuffle(usable, rnd);
  const out = [];
  let gi = 0;
  const n = SHAPE_ROTATION.length;
  for (const s of subjects) {
    if (out.length >= count) break;
    for (let off = 0; off < n; off++) {
      const shape = SHAPE_ROTATION[(gi + off) % n];
      const bank = STEMS[shape];
      const stem = bank[Math.floor(gi / n) % bank.length];
      const built = buildShape(shape, s, usable, stem, rnd);
      if (built) {
        const options = shuffle(built.options, rnd);
        out.push({
          id: `live:${shape}:${s.title}`.replace(/ /g, '_'),
          prompt: built.prompt, options, correctIndex: options.indexOf(built.answer),
          categoryID, difficulty: difficulty(s),
          explanation: firstSentence(s.extract || s.description || ''),
          sourceTitle: s.title, sourceURL: s.pageURL || null, templateID: shape,
        });
        break;
      }
    }
    gi += 1;
  }
  return out;
}
