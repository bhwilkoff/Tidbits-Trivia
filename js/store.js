// Tidbits — domain config + local persistence (web). Mirrors the Apple
// TriviaCategory / GameMode / RecordsStore. Records + streak live in
// localStorage (the per-ecosystem sync island; sign-in sync is later).

export const SITE_URL = 'https://tidbitstrivia.com';

// Tidbits Club — the web's paid tier (MONETIZATION §4a). Web sells via a Merchant of
// Record (best margin; MoR handles VAT/sales tax). Each plan's `checkout` is the MoR
// hosted-checkout URL — OWNER fills these once the MoR (Paddle / Lemon Squeezy) products
// exist; until then the buttons show an honest "billing setup in progress" state.
// The Worker webhook (workers/tidbits-auth) then writes the entitlement on purchase.
export const CLUB = {
  pitch: "Ranked seasons, a map of everything you know, and a library of every fact you've learned.",
  pillars: [
    ['🏆', 'Ranked Seasons', 'A calendar-driven climb — and your live pub nights count too.'],
    ['🗺️', 'Knowledge Atlas', 'A map of what you actually know, by domain, over time.'],
    ['📚', 'Story Archive', "Every fact you've learned, kept forever and searchable."],
    ['🧭', 'Expeditions', 'Multi-week campaigns that turn a session game into a pursuit.'],
  ],
  plans: [
    { id: 'lifetime', name: 'Founding Member', price: '$79.99', tag: 'Lifetime · first 90 days only', accent: '#FF5C5C', checkout: '' },
    { id: 'annual',   name: 'Tidbits Club',    price: '$29.99', tag: 'per year · best value',        accent: '#2D5BFF', checkout: '' },
    { id: 'monthly',  name: 'Tidbits Club',    price: '$3.99',  tag: 'per month',                    accent: '#2D5BFF', checkout: '' },
  ],
};

// Native-app promotion. Set a store URL when that app goes live; until then it
// renders as "Coming soon" on the home screen. Keep in lockstep with releases.
export const APP_STORES = [
  { id: 'ios', label: 'App Store', sub: 'iPhone · iPad · Apple TV', url: null },
  { id: 'android', label: 'Google Play', sub: 'Android phone & tablet', url: null },
];

export const POPS = ['#FF5C5C', '#2D5BFF', '#FFC93C', '#2FCB8A', '#8B5CF6', '#FF5DA2'];

export const CATEGORIES = [
  { id: 'mixed', name: 'Mixed Bag', symbol: '🔀', colorIndex: 0, blurb: 'A little of everything.' },
  { id: 'history', name: 'History', symbol: '📜', colorIndex: 1, blurb: 'People, places, and the past.' },
  { id: 'science', name: 'Science', symbol: '⚛️', colorIndex: 3, blurb: 'How the universe works.' },
  { id: 'geography', name: 'Geography', symbol: '🌎', colorIndex: 4, blurb: 'The whole wide world.' },
  { id: 'arts', name: 'Arts & Lit', symbol: '🎭', colorIndex: 5, blurb: 'Books, art, and culture.' },
  { id: 'screen', name: 'Film & TV', symbol: '🎬', colorIndex: 0, blurb: 'The big and small screen.' },
  { id: 'music', name: 'Music', symbol: '🎵', colorIndex: 2, blurb: 'From Bach to beats.' },
  { id: 'sports', name: 'Sports', symbol: '🏆', colorIndex: 1, blurb: 'Games and the greats.' },
];
export const catColor = (c) => POPS[c.colorIndex % POPS.length];

// Knowledge-cartography math — mirror of Core/Store/ProgressStats.swift.
// Seven domains (every category but "mixed"); gentle triangular level curve.
export const PROGRESS = {
  domains: ['history', 'science', 'geography', 'arts', 'screen', 'music', 'sports'],
  wedgeCorrect: 15,
  wedgeAccuracy: 0.60,
  threshold: (level) => 5 * level * (level + 1) / 2,
  level(correct) { let l = 0; while (this.threshold(l + 1) <= correct) l++; return l; },
};
export const catById = (id) => CATEGORIES.find((c) => c.id === id) || CATEGORIES[0];

export const MODES = {
  classic: { id: 'classic', title: 'Classic', blurb: 'Ten questions. Speed counts.', perQuestion: 20, count: 10, accent: '#2D5BFF' },
  timeAttack: { id: 'timeAttack', title: 'Time Attack', blurb: 'How many in 60 seconds?', perQuestion: null, globalClock: 60, count: 25, accent: '#FF5C5C' },
  survival: { id: 'survival', title: 'Survival', blurb: 'One wrong answer ends it.', perQuestion: 15, count: 99, accent: '#8B5CF6' },
  stake: { id: 'stake', title: 'Stake', blurb: 'Bet your confidence. No risk.', perQuestion: 30, count: 8, accent: '#2FCB8A' },
  sweep: { id: 'sweep', title: 'Sweep', blurb: 'Fill the set. Beat your best.', perQuestion: 12, count: 12, accent: '#13B6C9' },
  pictureId: { id: 'pictureId', title: 'Picture ID', blurb: 'Name what you see.', perQuestion: 20, count: 10, accent: '#FF5DA2' },
  thisOrThat: { id: 'thisOrThat', title: 'Which First?', blurb: 'Which came first?', perQuestion: 12, count: 10, accent: '#8B5CF6' },
  closestCall: { id: 'closestCall', title: 'Closest Call', blurb: 'How close can you get?', perQuestion: 25, count: 8, accent: '#FFC93C' },
  ordering: { id: 'ordering', title: 'In Order', blurb: 'Arrange them in time.', perQuestion: 35, count: 6, accent: '#2D5BFF' },
  matching: { id: 'matching', title: 'Match Up', blurb: 'Link each pair.', perQuestion: 40, count: 6, accent: '#FF5C5C' },
  typeAnswer: { id: 'typeAnswer', title: 'Name It', blurb: 'Type the answer.', perQuestion: 25, count: 8, accent: '#2FCB8A' },
  oddOneOut: { id: 'oddOneOut', title: 'Odd One Out', blurb: "Which doesn't belong?", perQuestion: 20, count: 8, accent: '#8B5CF6' },
  ladder: { id: 'ladder', title: 'Ladder', blurb: 'Climb from easy to hard.', perQuestion: 20, count: 10, accent: '#FF5C5C' },
  enumerate: { id: 'enumerate', title: 'Name as Many', blurb: 'How many can you name?', perQuestion: 60, count: 3, accent: '#13B6C9' },
  barTrivia: { id: 'barTrivia', title: 'Trivia Night', blurb: 'Host a night. Every kind of round.', perQuestion: 20, count: 20, accent: '#FF5C5C' },
  mix: { id: 'mix', title: 'Custom Mix', blurb: 'Your picked modes, shuffled together.', perQuestion: 20, count: 10, accent: '#13B6C9' },
  daily: { id: 'daily', title: 'Daily Tidbit', blurb: 'Everyone’s puzzle. Keep your streak.', perQuestion: 30, count: 7, accent: '#FFC93C' },
  // Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 1"). Never added to
  // ALL_MODES (the free Customize/Surprise-Me pool) — it has its own Home entry point.
  weakSpot: { id: 'weakSpot', title: 'Weak-Spot Arena', blurb: 'Turn your misses into a round.', perQuestion: 20, count: 10, accent: '#8B5CF6' },
};

// Trivia Night ("bar trivia") — a configurable night of themed rounds, each
// round drawing one question TYPE, so one night pulls from EVERY type. A client
// meta-mode over the shape-routing game loop (mirror of NightPlan.swift).
export const NIGHT = {
  kinds: ['classic', 'pictureId', 'thisOrThat', 'closestCall', 'ordering', 'matching', 'typeAnswer', 'oddOneOut', 'enumerate'],
  roundTitle: {
    classic: 'General Knowledge', pictureId: 'Picture Round', thisOrThat: 'Which Came First?',
    closestCall: 'Closest Wins', ordering: 'Put Them In Order', matching: 'Match-Up',
    typeAnswer: 'Name It', oddOneOut: 'Odd One Out', enumerate: 'Name As Many',
  },
  // Per-question clock by question SHAPE (a night mixes shapes in one run).
  shapeBudget(q) {
    if (!q) return 25;
    if (q.enumerate) return 60;
    if (q.matching) return 40;
    if (q.ordering) return 35;
    if (q.closest) return 25;
    if (q.accepted) return 25;
    if (q.image || q.imageURL) return 22;
    return 20;
  },
  presets: [
    { name: 'Quick Night', blurb: '3 rounds · ~12 questions', rounds: [['classic', 5], ['pictureId', 4], ['closestCall', 3]] },
    { name: 'Pub Night', blurb: '5 rounds · ~22 questions', rounds: [['classic', 6], ['pictureId', 4], ['thisOrThat', 4], ['closestCall', 4], ['oddOneOut', 4]] },
    { name: 'The Works', blurb: 'Every question type · ~28', rounds: [['classic', 4], ['pictureId', 4], ['thisOrThat', 4], ['closestCall', 4], ['ordering', 4], ['matching', 4], ['typeAnswer', 4], ['oddOneOut', 4], ['enumerate', 2]] },
  ],
};

// Modes that may have spaced-review corpus MCQs woven in — only the corpus-native
// MCQ modes; the bundled-set modes have their own shapes a stray MCQ can't render in.
export const REVIEW_MODES = new Set(['classic', 'timeAttack', 'survival', 'stake', 'sweep', 'ladder']);

// Stake mode's fixed confidence-chip budget (sum of count == mode.count). Spending
// more on one question leaves fewer for the rest — that scarcity is what makes it
// calibration. Adds-only: a wrong answer earns 0 but the chip is spent (Decision 022).
export const STAKE_BUDGET = [
  { value: 3, label: 'Sure', count: 2 },
  { value: 2, label: 'Likely', count: 3 },
  { value: 1, label: 'Hunch', count: 3 },
];

export function dayKey(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const LS = {
  get(k, fallback) { try { return JSON.parse(localStorage.getItem(k)) ?? fallback; } catch { return fallback; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* quota */ } },
};

export const Store = {
  _seen: new Set(LS.get('tidbits.seen', [])),

  seenHas(id) { return this._seen.has(id); },
  markSeen(ids) {
    ids.forEach((id) => this._seen.add(id));
    if (this._seen.size > 9000) this._seen.clear();
    LS.set('tidbits.seen', [...this._seen]);
  },
  resetSeen() { this._seen.clear(); localStorage.removeItem('tidbits.seen'); },

  records() { return LS.get('tidbits.records', []); },
  addRecord(rec, countsForStreak = true) {
    const all = this.records();
    all.unshift(rec);
    LS.set('tidbits.records', all.slice(0, 500));
    // Archive catch-ups of past Dailies don't feed the streak (R-DAILY-1).
    if (rec.mode === 'daily' && countsForStreak) this._bumpStreak();
  },

  // R-DAILY-1: per-day Daily results — first completion locks the day.
  dailyScore(day) { return LS.get('tidbits.daily.results', {})[day] ?? null; },
  allDaily() { return LS.get('tidbits.daily.results', {}); },
  recordDaily(day, score) {
    const m = LS.get('tidbits.daily.results', {});
    if (m[day] != null) return;
    m[day] = score;
    LS.set('tidbits.daily.results', m);
  },
  // Adopt the signed-in account's authoritative score for a day (overwrites local). Used
  // ONLY by cross-device sync to reconcile a conflict — gameplay stays first-wins.
  adoptDaily(day, score) {
    const m = LS.get('tidbits.daily.results', {});
    m[day] = score;
    LS.set('tidbits.daily.results', m);
  },
  bestScore(mode) {
    return this.records().filter((r) => r.mode === mode).reduce((m, r) => Math.max(m, r.score), 0);
  },
  lifetime() {
    const recs = this.records();
    const correct = recs.reduce((s, r) => s + r.correct, 0);
    const total = recs.reduce((s, r) => s + r.total, 0);
    return { games: recs.length, correct, total, acc: total ? Math.round((correct / total) * 100) : 0 };
  },
  // Topic Levels (depth) + The Pie (breadth) derived from per-game history —
  // one row per knowledge domain (SOLO-BACKLOG M3 + M4; mirror of ProgressMath).
  progress() {
    const recs = this.records();
    return PROGRESS.domains.map((id) => {
      const mine = recs.filter((r) => r.categoryID === id);
      const correct = mine.reduce((s, r) => s + r.correct, 0);
      const total = mine.reduce((s, r) => s + r.total, 0);
      const acc = total ? correct / total : 0;
      const level = PROGRESS.level(correct);
      const lo = PROGRESS.threshold(level), hi = PROGRESS.threshold(level + 1);
      return { id, correct, total, acc, level,
        levelProgress: hi === lo ? 1 : Math.min(1, Math.max(0, (correct - lo) / (hi - lo))),
        hasWedge: correct >= PROGRESS.wedgeCorrect && acc >= PROGRESS.wedgeAccuracy };
    });
  },

  // F1 calibration: lifetime per-tier {hits,total} across Stake rounds.
  calibration() { return LS.get('tidbits.calibration', {}); },
  addCalibration(outcomes) {
    const c = this.calibration();
    for (const [tier, o] of Object.entries(outcomes || {})) {
      if (!o.total) continue;
      const cur = c[tier] || { hits: 0, total: 0 };
      cur.hits += o.hits; cur.total += o.total; c[tier] = cur;
    }
    LS.set('tidbits.calibration', c);
  },

  // Gameplay setting: spaced re-asking of missed questions (default on).
  reviewEnabled() { return LS.get('tidbits.reviewEnabled', true); },
  setReviewEnabled(v) { LS.set('tidbits.reviewEnabled', !!v); },

  streak() { return LS.get('tidbits.streak', { current: 0, best: 0, lastDay: '' }); },
  _bumpStreak() {
    const s = this.streak();
    const today = dayKey();
    if (s.lastDay === today) return;
    const y = new Date(); y.setDate(y.getDate() - 1);
    s.current = s.lastDay === dayKey(y) ? s.current + 1 : 1;
    s.best = Math.max(s.best, s.current);
    s.lastDay = today;
    LS.set('tidbits.streak', s);
  },

  // F4 answer-distribution telemetry: local, privacy-respecting per-option
  // counts keyed by question id ({ qid: [perOptionCount] }). No PII, no
  // network — the invisible foundation a backend later aggregates into the
  // "X% picked this" / Predict-the-Crowd reveal. Modes whose chosen index is
  // synthetic (0/right vs -1/wrong, not a real option pick) are skipped.
  _telemetrySkip: new Set(['closestCall', 'ordering', 'matching', 'typeAnswer', 'enumerate']),
  answerTelemetry() { return LS.get('tidbits.answerTelemetry', {}); },
  recordTelemetry(mode, answered) {
    if (this._telemetrySkip.has(mode)) return;
    const map = this.answerTelemetry();
    for (const a of answered) {
      const opts = a.q && a.q.options;
      if (!Array.isArray(opts) || opts.length < 2) continue;
      if (a.chosen == null || a.chosen < 0 || a.chosen >= opts.length) continue;
      const counts = map[a.q.id] || new Array(opts.length).fill(0);
      while (counts.length < opts.length) counts.push(0);
      counts[a.chosen]++;
      map[a.q.id] = counts;
    }
    if (Object.keys(map).length > 5000) { LS.set('tidbits.answerTelemetry', {}); return; }
    LS.set('tidbits.answerTelemetry', map);
  },
  answerDistribution(qid) { return this.answerTelemetry()[qid] || null; },

  // Missed facts for spaced review. `lastSeen` (added for Weak-Spot Arena,
  // docs/CLUB-FEATURES-BUILD.md "Feature 1") is the last time the question was
  // MISSED — the oldest-gap-first sort + "Missed X ago" caption both key off it.
  // Legacy entries predating this field simply sort as oldest (0).
  missed() { return LS.get('tidbits.missed', []); },
  recordMisses(answered) {
    const missed = this.missed();
    const byId = new Map(missed.map((m) => [m.id, m]));
    const now = Date.now();
    for (const a of answered) {
      if (a.correct) { const m = byId.get(a.q.id); if (m) m.resolved = true; }
      else {
        const ex = byId.get(a.q.id);
        if (ex) { ex.missCount++; ex.resolved = false; ex.lastSeen = now; }
        else { const m = { id: a.q.id, q: a.q, missCount: 1, resolved: false, lastSeen: now }; missed.push(m); byId.set(a.q.id, m); }
      }
    }
    LS.set('tidbits.missed', missed);
  },
  dueReview(limit = 2) {
    return this.missed().filter((m) => !m.resolved).sort((a, b) => b.missCount - a.missCount).slice(0, limit).map((m) => m.q);
  },

  // Story Archive (Club feature 2, docs/CLUB-FEATURES-BUILD.md "Feature 2"): every
  // question the player has ANSWERED (right or wrong), keyed by qid. Upserted from
  // the same place recordMisses/recordTelemetry are called (Game._persist), so
  // "seen" = any answer, not just a correct one — you met the fact either way.
  // R-MON-1: the in-moment story reveal (Question.explanation) stays FREE for
  // everyone, unchanged; this is a persistent, searchable ADDITIVE library over
  // data ordinary play already produces, storing the whole answered `q` snapshot
  // (mirrors `missed()`) so a story survives later corpus edits and can be
  // replayed via "Re-ask this".
  seenStories() { return LS.get('tidbits.stories', {}); },
  recordSeen(answered) {
    const map = this.seenStories();
    const now = Date.now();
    for (const a of answered) {
      const q = a.q; if (!q) continue;
      const ex = map[q.id];
      if (ex) { ex.last = now; if (a.correct) ex.everCorrect = true; }
      else map[q.id] = { id: q.id, q, first: now, last: now, everCorrect: !!a.correct, fav: false };
    }
    if (Object.keys(map).length > 9000) { LS.set('tidbits.stories', {}); return; }
    LS.set('tidbits.stories', map);
  },
  toggleStoryFavorite(id) {
    const map = this.seenStories();
    const ex = map[id]; if (!ex) return false;
    ex.fav = !ex.fav;
    LS.set('tidbits.stories', map);
    return ex.fav;
  },
  resetAll() {
    ['tidbits.records', 'tidbits.streak', 'tidbits.missed', 'tidbits.seen', 'tidbits.calibration', 'tidbits.answerTelemetry', 'tidbits.stories'].forEach((k) => localStorage.removeItem(k));
    this._seen.clear();
  },
};

// A question's displayable correct-answer text, shared by the Story Archive
// search/render and (via recordSeen's stored `q` snapshot) "Re-ask this" — mirrors
// the closest-value formatting `closestFmtVal` does inline in app.js, but Store
// stays framework-free of any single game-mode's UI concerns.
export function answerTextOf(q) {
  if (!q) return '';
  if (q.options && q.correctIndex != null) return q.options[q.correctIndex];
  if (q.closest) { const n = Math.round(q.closest.answer); return q.closest.unit ? `${n} ${q.closest.unit}` : String(n); }
  return '';
}

// "2 weeks ago" / "yesterday" — the web's Intl mirror of Apple's
// RelativeDateTimeFormatter, used only by Weak-Spot Arena's reason caption.
function relativeTime(ts) {
  if (!ts) return 'a while back';
  const mins = Math.round((Date.now() - ts) / 60000);
  if (mins < 1) return 'just now';
  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto', style: 'long' });
  if (mins < 60) return rtf.format(-mins, 'minute');
  const hours = Math.round(mins / 60);
  if (hours < 24) return rtf.format(-hours, 'hour');
  const days = Math.round(hours / 24);
  if (days < 30) return rtf.format(-days, 'day');
  const months = Math.round(days / 30);
  if (months < 12) return rtf.format(-months, 'month');
  return rtf.format(-Math.round(months / 12), 'year');
}

// Tidbits Club EXCLUSIVE — Weak-Spot Arena (docs/CLUB-FEATURES-BUILD.md "Feature
// 1"). The web mirror of the Apple `WeakSpotArena.build()`: a round built entirely
// from the player's own local miss history (Store.missed()) — most-missed + oldest
// gap first — topped up from weakest categories when true misses are thin.
// Transparent by construction: every question carries a plain "why you're seeing
// this" reason, never an opaque model.
export const WeakSpotArena = {
  roundSize: 10,
  // Below this many true misses, the round is topped up from weak categories.
  trueMissFloor: 4,
  // Target size when topping up with category-fill (not the full 10 — a round
  // mostly "shoring up X" stops being a *weak-spot* arena).
  fillTarget: 8,

  /** Build one round: { questions, reasons: {qid: reasonString}, missCount }.
   * `pull(categoryID, excludingIds, limit)` sources the category top-up — the
   * caller passes Corpus.pull so this generator stays a pure function of the
   * local miss store + whatever pull function it's given (easy to test). */
  build(pull) {
    const unresolved = Store.missed().filter((m) => !m.resolved && m.q)
      .sort((a, b) => b.missCount - a.missCount || (a.lastSeen || 0) - (b.lastSeen || 0));
    const questions = [];
    const reasons = {};
    const pickedIDs = new Set();
    for (const m of unresolved) {
      if (questions.length >= this.roundSize) break;
      if (pickedIDs.has(m.id)) continue;
      questions.push(m.q);
      pickedIDs.add(m.id);
      reasons[m.id] = `Missed ${relativeTime(m.lastSeen)} · ×${m.missCount}`;
    }
    const missCount = questions.length;

    if (missCount < this.trueMissFloor && typeof pull === 'function') {
      const weakest = Store.progress().filter((d) => d.total >= 3).sort((a, b) => a.acc - b.acc);
      for (const domain of weakest) {
        if (questions.length >= this.fillTarget) break;
        const pool = pull(domain.id, pickedIDs, this.fillTarget - questions.length) || [];
        for (const q of pool) {
          if (questions.length >= this.fillTarget) break;
          questions.push(q);
          pickedIDs.add(q.id);
          reasons[q.id] = `Shoring up ${catById(domain.id).name}`;
        }
      }
    }
    return { questions, reasons, missCount };
  },

  /** A genuine one-line sample from the player's own misses (MONETIZATION §4a:
   * "a real preview, never a nag") — the non-member Home-card pitch. */
  previewLine() {
    const unresolved = Store.missed().filter((m) => !m.resolved && m.q)
      .sort((a, b) => b.missCount - a.missCount);
    const m = unresolved[0];
    return m ? `Missed: “${m.q.prompt}” — Club turns misses like this into a round.` : null;
  },
};

// Tidbits Club EXCLUSIVE — Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2").
// The read side of Store.seenStories(): plain filtering + substring search, no
// ranking model — the corpus stays legible, never an opaque "for you" feed.
export const StoryArchive = {
  /** Every seen story, most-recently-encountered first. */
  list() {
    return Object.values(Store.seenStories()).sort((a, b) => b.last - a.last);
  },
  /** Distinct domains actually present, in canonical PROGRESS order — so filter
   * chips only ever show domains the player has actually played (never an empty
   * chip). */
  domainsSeen() {
    const present = new Set(this.list().map((s) => s.q.categoryID || 'mixed'));
    return PROGRESS.domains.filter((d) => present.has(d));
  },
  /** `filter`: null | 'fav' | 'missed' | 'gotit'. Plain substring match across
   * prompt/answer/story text — never a relevance model. */
  search(text, { domain = null, filter = null } = {}) {
    const needle = (text || '').trim().toLowerCase();
    return this.list().filter((s) => {
      const q = s.q;
      if (domain && (q.categoryID || 'mixed') !== domain) return false;
      if (filter === 'fav' && !s.fav) return false;
      if (filter === 'missed' && s.everCorrect) return false;
      if (filter === 'gotit' && !s.everCorrect) return false;
      if (!needle) return true;
      return (q.prompt || '').toLowerCase().includes(needle)
        || String(answerTextOf(q)).toLowerCase().includes(needle)
        || (q.explanation || '').toLowerCase().includes(needle);
    });
  },
  toggleFavorite(id) { return Store.toggleStoryFavorite(id); },
  count() { return this.list().length; },
  /** A genuine sample from the player's own archive (MONETIZATION §4a: "a real
   * preview, never a nag") — the non-member Records-row + #/archive pitch. */
  previewLine() {
    const s = this.list()[0];
    if (!s) return null;
    return `“${s.q.explanation || s.q.prompt}” — Club keeps every story you unlock, searchable forever.`;
  },
};
