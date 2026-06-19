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
  // Fame floor: a long intro is a strong, free notability proxy. Obscure stubs
  // ("X is an American actor.") are short — and unfun to be quizzed on.
  if (!e || e.length < 600) return false;
  const lt = (s.title || '').toLowerCase();
  if (lt.startsWith('list of') || lt.includes('(disambiguation)')) return false;
  if ((e || '').toLowerCase().includes('may refer to')) return false;
  if (/^\s*(\w+\s+){0,2}(person|human|man|woman|place|thing|object|name|surname|given name|topics?)\b/i.test(d)) return false;
  if (typeKey(s) === null) return false;   // un-typeable → can't guarantee typed distractors
  return true;
};

const stripParens = (t) => t.replace(/\s*\([^)]*\)/g, '');
const ABBREV = new Set('lit e.g i.e approx no vs etc st mt mr mrs ms dr fl ca jr sr col gen gov sen rep prof rev inc ltd co u.s u.k'.split(' '));
const firstSentence = (t) => {
  // Paren/abbreviation-aware so 'lit.' / '(…; lit. …)' / middle initials don't
  // truncate the clue mid-phrase.
  const s = (t || '').trim();
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '(' || ch === '[') depth++;
    else if ((ch === ')' || ch === ']') && depth > 0) depth--;
    else if (ch === '.' && depth === 0 && s[i + 1] === ' ') {
      const nxt2 = s[i + 2] || '';
      if (nxt2 === '' || nxt2 === nxt2.toUpperCase() && /[A-Z“”"'‘’]/.test(nxt2)) {
        let j = i - 1;
        while (j >= 0 && /[A-Za-z0-9.'\-]/.test(s[j])) j--;
        const tok = s.slice(j + 1, i);
        const letters = tok.replace(/[^A-Za-z]/g, '');
        const isAbbrev = letters && (letters.length <= 1 || ABBREV.has(tok.toLowerCase().replace(/\.+$/, '')));
        if (!isAbbrev) return s.slice(0, i + 1);
      }
    }
  }
  return s;
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

const FUNCTION_WORDS = new Set('the of and a an in on at to for by with from as or de von van al'.split(' '));
const COMMON_WORDS = new Set(('empire battle war wars kingdom dynasty republic treaty river mountain mountains lake island islands city town county state states united nation national american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western great greater new saint university college school company group band series film movie novel book award club team teams league party system century world people region province district area force army navy air language family order house song album season game games sport sports festival prize federal royal international association federation union organization museum park station bridge building tower palace castle church cathedral temple championship cup first second').split(' '));

function leaks(answer, prompt) {
  const p = prompt.toLowerCase();
  for (const t of new Set((answer.toLowerCase().match(/[a-z]{4,}/g) || []).filter((w) => !COMMON_WORDS.has(w)))) {
    if (p.includes(t)) return true;
  }
  return false;
}

function redact(text, title) {
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let out = text;
  const bare = stripParens(title).trim();
  for (const needle of new Set([title, bare])) {
    if (needle) out = out.replace(new RegExp(esc(needle), 'gi'), '—————');
  }
  // Leading proper-noun run (≥2 words) — catches full-name variants.
  out = out.replace(/^(The |A |An )?((?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of |the |and |de |von |van |al-)?[A-Z][\w’'.\-]*)+)/, (m, p1) => (p1 || '') + '—————');
  // Each CONTENT title word wherever it appears.
  for (const w of bare.split(/[^A-Za-z’'\-]+/)) {
    if (w.length < 3 || FUNCTION_WORDS.has(w.toLowerCase())) continue;
    out = out.replace(new RegExp('\\b' + esc(w) + "(?:’s|'s|s|es)?\\b", 'gi'), '—————');
  }
  out = out.replace(/—————(?:[\s,’'.\–\-]+(?:of|the|and)?\s*—————)+/gi, '—————').replace(/\s{2,}/g, ' ').trim();
  return out;
}

// Siblings ranked by description word-overlap (same-domain → plausible).
// lengthMatch (when set) prefers similar-length values to kill the
// "longest option is the answer" tell.
// Type-matched distractors (mirror of generate_corpus.py): distractors MUST be
// the same TYPE as the answer. Type comes from the Wikipedia short description's
// head noun (synonym-folded). Draw only from the subject's type; [] (→ drop) if
// fewer than 3 same-type siblings — never widen to a wrong type.
const TYPE_LEADING = new Set('american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western central ancient modern medieval former national international royal imperial classical contemporary professional famous notable major minor large small great greater lesser old new young senior junior fictional mythological historical traditional popular official public private federal scottish irish welsh dutch swedish norwegian danish polish turkish greek roman egyptian persian arab arabic jewish canadian australian mexican brazilian argentine chilean austrian swiss belgian portuguese finnish hungarian czech romanian indonesian filipino vietnamese thai largest smallest oldest'.split(' '));
const TYPE_STOP = /\b(in|of|from|for|by|on|at|near|during|between|that|which|who|known|with|to|and|or|located|based|set)\b/i;
const TYPE_FOLD = { singer: 'musician', songwriter: 'musician', 'singer-songwriter': 'musician', rapper: 'musician', guitarist: 'musician', pianist: 'musician', drummer: 'musician', bassist: 'musician', vocalist: 'musician', band: 'musician', duo: 'musician', composer: 'musician', actress: 'actor', filmmaker: 'director', novelist: 'writer', author: 'writer', poet: 'writer', playwright: 'writer', screenwriter: 'writer', essayist: 'writer', journalist: 'writer', physicist: 'scientist', chemist: 'scientist', biologist: 'scientist', mathematician: 'scientist', astronomer: 'scientist', geologist: 'scientist', economist: 'scientist', psychologist: 'scientist', inventor: 'scientist', footballer: 'athlete', player: 'athlete', cyclist: 'athlete', swimmer: 'athlete', boxer: 'athlete', wrestler: 'athlete', sprinter: 'athlete', runner: 'athlete', golfer: 'athlete', village: 'settlement', town: 'settlement', city: 'settlement', municipality: 'settlement', commune: 'settlement', capital: 'settlement', mountain: 'peak', volcano: 'peak' };
function typeKey(subject) {
  let d = (subject.description || '').replace(/\([^)]*\)/g, '').split(',')[0].trim().replace(/\.$/, '').toLowerCase();
  const m = d.match(TYPE_STOP); if (m) d = d.slice(0, m.index);
  let toks = d.match(/[a-z][a-z\-]+/g) || [];
  while (toks.length && TYPE_LEADING.has(toks[0])) toks = toks.slice(1);
  if (!toks.length) return null;
  const k = toks[toks.length - 1];
  return TYPE_FOLD[k] || k;
}
function typedDistractors(subject, pool, rnd, valueFn, exclude, lengthMatch) {
  const kt = typeKey(subject); if (!kt) return [];
  const excl = (exclude || '').toLowerCase(); const seen = new Set(); const cands = [];
  for (const c of pool) {
    if (c.title === subject.title || typeKey(c) !== kt) continue;
    const v = (valueFn(c) || '').trim();
    if (!v || v.toLowerCase() === excl || seen.has(v.toLowerCase())) continue;
    seen.add(v.toLowerCase());
    cands.push({ v, lenPen: lengthMatch != null ? -Math.abs(v.length - lengthMatch) : 0 });
  }
  if (cands.length < 3) return [];
  cands.sort((a, b) => b.lenPen - a.lenPen);
  return shuffle(cands.slice(0, Math.max(9, 8)), rnd).slice(0, 3).map((x) => x.v);
}
const titleDistractors = (s, pool, rnd) => typedDistractors(s, pool, rnd, (c) => stripParens(c.title), stripParens(s.title), null);
const descDistractors = (s, pool, rnd) => typedDistractors(s, pool, rnd, (c) => c.description, s.description, (s.description || '').length);

function difficulty(s) {
  // Above the fame floor (600), a longer intro = more famous = easier.
  const n = (s.extract || '').length;
  return n >= 2000 ? 2 : n >= 1000 ? 3 : 4;
}

// --- "Describe & identify" — the bar-trivia shape (mirror of generate_corpus.py)
// Leads with the distinguishing facts, asks a natural "who/what is this?". The
// old robotic framings + the "what kind of thing is X?" categorize shape are gone.
const MONTHS = new Set('january february march april may june july august september october november december'.split(' '));
const TYPE_NOUNS = new Set('actor actress singer musician composer songwriter rapper band writer author poet novelist playwright journalist artist painter sculptor director filmmaker producer scientist physicist chemist biologist mathematician astronomer economist politician philosopher activist explorer inventor architect dancer comedian footballer player athlete cyclist swimmer boxer golfer film movie television series show novel book album song single painting sculpture poem play opera symphony team club city town country river mountain lake dynasty empire'.split(' '));
const NATIONALITIES = new Set('polish french american british english german italian russian japanese chinese spanish dutch canadian australian indian brazilian mexican swedish norwegian danish finnish greek roman egyptian persian turkish irish scottish welsh austrian swiss belgian portuguese hungarian czech romanian korean vietnamese thai argentine chilean colombian peruvian israeli iranian iraqi syrian lebanese moroccan nigerian kenyan ethiopian ukrainian serbian croatian bulgarian icelandic'.split(' '));
const CLUE_GENERIC = new Set([...COMMON_WORDS, ...TYPE_LEADING, ...TYPE_NOUNS, ...NATIONALITIES,
  ...'this the a an was is were are best known famous noted also who which that based located near former'.split(' ')]);

function informativeTokens(clue) {
  // Strip parentheticals first — a '(born 1963)' birth date is birthday-guessing,
  // not a quizzable clue; pronunciations/IPA are noise.
  const c = clue.replace(/\([^)]*\)/g, '');
  const proper = new Set((c.match(/\b[A-Z][A-Za-z'’\-]{2,}\b/g) || []).map((w) => w.toLowerCase())
    .filter((w) => !CLUE_GENERIC.has(w) && !MONTHS.has(w)));
  const years = new Set(c.match(/\b(?:1\d{3}|20\d{2})\b/g) || []);
  return proper.size + years.size;
}

// Decided by the type HEAD-NOUN (typeKey), not a loose word match — a novel
// "by American author X" must NOT read as a person.
const PERSON_TYPEKEYS = new Set('actor actress musician writer scientist athlete director painter singer composer poet novelist author journalist sculptor architect engineer politician philosopher economist historian activist explorer inventor dancer comedian model conductor pianist guitarist rapper businessman entrepreneur king queen emperor empress monarch president general admiral saint pope sultan tsar duke earl baron knight prince princess priest bishop rabbi imam nun monk lawyer diplomat soldier aristocrat theologian'.split(' '));
function isPerson(s) {
  const k = typeKey(s);
  if (PERSON_TYPEKEYS.has(k)) return true;
  if (k !== null) return false;   // typed as a non-person thing
  return /\(\s*\d{3,4}\s*[–-]|\bborn\b/.test(s.extract || '');
}

// Leading proper-noun run (the full birth name, which differs from the title).
const LEAD = /^\s*((?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of|the|and|de|von|van|al|da|di)?\s*[A-Z][\w’'.\-]*)*)\s*(?:\([^)]*\))?\s+(?:was|is|were|are)\s+(?:a|an|the)\s+(.+)$/;

function blankName(text, title) {
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let out = text; const bare = stripParens(title).trim();
  for (const needle of new Set([title, bare])) if (needle) out = out.replace(new RegExp(esc(needle), 'gi'), '—————');
  for (const w of bare.split(/[^A-Za-z’'\-]+/)) {
    if (w.length < 3 || FUNCTION_WORDS.has(w.toLowerCase())) continue;
    out = out.replace(new RegExp('\\b' + esc(w) + "(?:’s|'s|s|es)?\\b", 'gi'), '—————');
  }
  return out.replace(/—————(?:[\s,’'.\–\-]+(?:of|the|and)?\s*—————)+/gi, '—————').replace(/\s{2,}/g, ' ').trim();
}

function firstN(text, n) {
  const out = []; let rest = (text || '').trim();
  for (let k = 0; k < n && rest; k++) { const s = firstSentence(rest); out.push(s.trim()); rest = rest.slice(s.length).trimStart(); }
  return out.join(' ');
}

function reframe(sentence, s) {
  // Bare descriptive phrase ("American actor best known for …"); the stem frames it.
  const m = sentence.match(LEAD);
  return m ? blankName(m[2].trim(), s.title) : null;
}

const STEMS = {
  describe_person: ['This %s — who is this?', 'Name this %s.', 'Who is the %s?', 'Which %s?'],
  describe_thing: ['Name this %s.', 'Which %s?', 'Name the %s.'],
  cloze: ['Fill in the blank: “%s”', 'Complete it: “%s”', 'Which name completes this? “%s”'],
};
const SHAPE_ROTATION = ['describe', 'cloze', 'describe', 'describe', 'cloze'];

function buildShape(shape, s, pool, stem, rnd) {
  const fmt = (v) => stem.replace('%s', v);
  if (shape === 'describe') {
    // FIRST sentence only — a 2-sentence clue reads awkwardly under "Name this …?".
    const c = reframe(cleanClue(firstSentence(s.extract || '')), s);
    if (!c || c.length < 30 || informativeTokens(c) < 2) return null;
    const clue = c.replace(/[.\s]+$/, '').trim();
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    const ans = stripParens(s.title); return { prompt: fmt(clue), options: [ans, ...ds], answer: ans };
  }
  if (shape === 'cloze') {
    const sent = cleanClue(firstSentence(s.extract || '')); const bare = stripParens(s.title); let clozed = null;
    for (const needle of [s.title, bare]) {
      if (needle && sent.toLowerCase().includes(needle.toLowerCase())) {
        clozed = sent.replace(new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), '_____'); break;
      }
    }
    if (!clozed) { const m = sent.match(LEAD); if (m) { const i = sent.indexOf(m[1]); clozed = sent.slice(0, i) + '_____' + sent.slice(i + m[1].length); } }
    if (!clozed || clozed.length < 30 || informativeTokens(clozed) < 2) return null;
    const ds = titleDistractors(s, pool, rnd); if (ds.length !== 3) return null;
    return { prompt: fmt(clozed), options: [bare, ...ds], answer: bare };
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
    const person = isPerson(s);
    for (let off = 0; off < n; off++) {
      const shape = SHAPE_ROTATION[(gi + off) % n];
      const bank = shape === 'describe' ? (person ? STEMS.describe_person : STEMS.describe_thing) : STEMS[shape];
      const stem = bank[Math.floor(gi / n) % bank.length];
      const built = buildShape(shape, s, usable, stem, rnd);
      if (built) {
        // Never ship a question whose answer leaks into the prompt.
        if (leaks(built.answer, built.prompt)) continue;
        if (built.prompt.length > 320 || /[Ͱ-ϿЀ-ӿ֐-ۿ぀-ヿ一-鿿가-힯∀-⋿⟨-⟯]/.test(built.prompt)) continue;
        const options = shuffle(built.options, rnd);
        out.push({
          id: `live:${shape}:${s.title}`.replace(/ /g, '_'),
          prompt: built.prompt, options, correctIndex: options.indexOf(built.answer),
          categoryID, difficulty: difficulty(s),
          explanation: cleanClue(firstSentence(s.extract || s.description || '')),
          sourceTitle: s.title, sourceURL: s.pageURL || null, templateID: shape,
        });
        break;
      }
    }
    gi += 1;
  }
  return out;
}
