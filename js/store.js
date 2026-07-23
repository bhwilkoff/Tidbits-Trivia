// Tidbits — domain config + local persistence (web). Mirrors the Apple
// TriviaCategory / GameMode / RecordsStore. Records + streak live in
// localStorage (the per-ecosystem sync island; sign-in sync is later).

import { fnv1a64 } from './engine.js';

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
  // Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 3"). Never added to
  // ALL_MODES — it has its own Home entry point + the resume-across-sessions flow.
  // `count` is a cap only (the actual per-session length is whatever's left of the
  // run); 45s/Q is generous — endurance, not speed.
  marathon: { id: 'marathon', title: 'Marathon', blurb: '200 questions. Play it across as many sittings as you like.', perQuestion: 45, count: 200, accent: '#13B6C9' },
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
    ['tidbits.records', 'tidbits.streak', 'tidbits.missed', 'tidbits.seen', 'tidbits.calibration', 'tidbits.answerTelemetry', 'tidbits.stories', 'tidbits.marathonRun', 'tidbits.marathonScores', 'tidbits.expeditionProgress', 'tidbits.expeditionCertificates'].forEach((k) => localStorage.removeItem(k));
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

// Tidbits Club EXCLUSIVE — Marathon (docs/CLUB-FEATURES-BUILD.md "Feature 3"). A
// 200-question graded endurance run whose load-bearing NEW mechanic is RESUME
// ACROSS SESSIONS: an in-progress MarathonRun (localStorage) holds a seed + the
// FIXED ordered id list drawn once from that seed (mirrors the Daily's
// deterministic pickDaily rank-and-slice — same fnv1a64 rank, just keyed by a
// per-run seed instead of a calendar day) + currentIndex + one result per
// answered question. Persisted after EVERY answer (Marathon.record, never
// batched) so a tab close/crash never loses progress. On finish, writes a
// permanent MarathonScore to history and clears the run. Deliberately writes NO
// GameRecord/MissedFact/SeenStory — a single session's slice of a multi-session
// run would misreport lifetime stats (mirrors the Apple reference).
const MARATHON_RUN_KEY = 'tidbits.marathonRun';
const MARATHON_HISTORY_KEY = 'tidbits.marathonScores';

function marathonSeed() {
  try { if (window.crypto && window.crypto.randomUUID) return crypto.randomUUID(); } catch {}
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export const Marathon = {
  defaultLength: 200,

  // ?marathonlen=<n> shortens a run for TESTING only (so one can be played to
  // completion quickly) — this only ever narrows the count below 200, never
  // widens it; production (no param) always sees the full 200.
  get runLength() {
    try {
      const raw = new URLSearchParams(location.search).get('marathonlen');
      const n = raw != null ? parseInt(raw, 10) : NaN;
      if (Number.isFinite(n) && n > 0) return Math.min(n, this.defaultLength);
    } catch {}
    return this.defaultLength;
  },

  /** The in-progress run, if any (at most one). */
  inProgress() { return LS.get(MARATHON_RUN_KEY, null); },

  /** Start a fresh run, discarding any stale one (Start Over). `allIds` is
   * every corpus question id — the caller passes Corpus.questions.map(q =>
   * q.id) so Store stays framework-free of the corpus loader (same pattern as
   * WeakSpotArena's `pull` param). The ids are fixed forever at creation from a
   * fresh seed — a resume always continues into the SAME set. */
  startNew(allIds) {
    const seed = marathonSeed();
    const count = Math.min(this.runLength, allIds.length);
    const ids = allIds
      .map((id) => [fnv1a64(`marathon:${seed}:${id}`), id])
      .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : (a[1] < b[1] ? -1 : 1)))
      .slice(0, count)
      .map((x) => x[1]);
    const run = { seed, ids, currentIndex: 0, results: [], startedAt: Date.now(), lastPlayedAt: Date.now() };
    LS.set(MARATHON_RUN_KEY, run);
    return run;
  },

  /** The ids remaining to play THIS session — from currentIndex to the end
   * (what a resumed, or fresh, session actually loads into the engine). */
  remainingIds(run) { return run.ids.slice(Math.min(run.currentIndex, run.ids.length)); },

  /** Persist one answer immediately — called after every submitted answer so a
   * crash/quit/tab-close never loses progress (the whole point of Marathon). */
  record(run, { qid, categoryId, difficulty, correct }) {
    run.results.push({ qid, categoryId, difficulty: difficulty || 1, correct: !!correct });
    run.currentIndex = run.results.length;
    run.lastPlayedAt = Date.now();
    LS.set(MARATHON_RUN_KEY, run);
  },

  /** The run just reached its full length — write the permanent MarathonScore
   * (difficulty-weighted score, correct/total, per-domain breakdown, duration)
   * and clear the in-progress run. */
  finish(run) {
    const results = run.results;
    const correct = results.filter((r) => r.correct).length;
    // A plain difficulty-weighted score (10 pts × difficulty per correct
    // answer) — transparent by construction, no hidden model (mirrors Apple).
    const score = results.filter((r) => r.correct).reduce((sum, r) => sum + r.difficulty * 10, 0);
    const durationSeconds = Math.max(1, Math.round((Date.now() - run.startedAt) / 1000));
    const domainBreakdown = PROGRESS.domains.map((id) => {
      const rows = results.filter((r) => r.categoryId === id);
      return { categoryId: id, correct: rows.filter((r) => r.correct).length, total: rows.length };
    });
    const entry = { date: Date.now(), score, correct, total: results.length, durationSeconds, domainBreakdown };
    const history = this.history();
    history.unshift(entry);
    LS.set(MARATHON_HISTORY_KEY, history.slice(0, 200));
    localStorage.removeItem(MARATHON_RUN_KEY);
    return entry;
  },

  /** Past completed runs, most recent first — the permanent Marathon history. */
  history() { return LS.get(MARATHON_HISTORY_KEY, []); },

  /** A real, concrete illustration (MONETIZATION §4a: "a real preview, never a
   * nag"). Marathon has no free-tier data to draw a genuine sample from (unlike
   * Weak-Spot/Story Archive, which are built from ordinary free play) — so the
   * non-member pitch is an honest, specific illustration of the scorecard. */
  previewLine() {
    return 'See exactly where you stand — e.g. Geography 91% · History 64% — across a 200-question run you can pause and resume anytime.';
  },
};

export function marathonAccuracy(entry) { return entry && entry.total ? entry.correct / entry.total : 0; }

// Tidbits Club EXCLUSIVE — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md "Feature
// 4"). A transparent, interpreted layer over the SAME per-game rows the free
// Topic Levels / Pie already read (Store.records() categoryID/correct/total) —
// additive, never a lock on what's already free (R-MON-1). PURE DERIVATION, no
// new storage; no opaque "mastery score" — every number here is a plain count.
//
// A game record carries no per-answer timestamp on the web (mirrors Apple's
// AnswerDetail), so month-bucketing uses each GAME's `at`/`date` for ALL of
// that game's answers — the same granularity the corpus already persists.
// Trailing 12 months only; older history keeps feeding the free lifetime
// Pie/Levels but drops out of the Atlas's month math.
function atlasMonthsAgo(ts, now = Date.now()) {
  const d = new Date(ts), n = new Date(now);
  return Math.max(0, (n.getFullYear() - d.getFullYear()) * 12 + (n.getMonth() - d.getMonth()));
}
function atlasRows() {
  return Store.records()
    .map((r) => ({ categoryID: r.categoryID, correct: r.correct, total: r.total, ts: r.at || (r.date ? Date.parse(r.date) : Date.now()) }))
    .filter((r) => atlasMonthsAgo(r.ts) <= 11);
}
// Below `KnowledgeAtlas.sampleFloor` answers in a window, a read is withheld
// rather than shown noisy — "don't flag a domain with <8 answers" (design spec).
function atlasQuarterAccuracy(rows, lo, hi) {
  const mine = rows.filter((r) => { const m = atlasMonthsAgo(r.ts); return m >= lo && m <= hi; });
  const total = mine.reduce((s, r) => s + r.total, 0);
  if (total < KnowledgeAtlas.sampleFloor) return null;
  const correct = mine.reduce((s, r) => s + r.correct, 0);
  return correct / total;
}

export const KnowledgeAtlas = {
  sampleFloor: 8,
  strongThreshold: 0.70,
  decayDelta: 0.12,

  /** Per-domain trailing-12-month standing, domains never played omitted (same
   * convention as Store.progress() for the free Pie/Levels). `trajectoryDelta`
   * is this-quarter (months 0-2) minus prior-quarter (months 3-5) accuracy;
   * null when either quarter is too thin to read — an honest "not enough
   * history yet" rather than a noisy arrow. */
  domains() {
    const rows = atlasRows();
    return PROGRESS.domains.map((id) => {
      const mine = rows.filter((r) => r.categoryID === id);
      if (!mine.length) return null;
      const correct = mine.reduce((s, r) => s + r.correct, 0);
      const total = mine.reduce((s, r) => s + r.total, 0);
      const recentAccuracy = atlasQuarterAccuracy(mine, 0, 2);
      const priorAccuracy = atlasQuarterAccuracy(mine, 3, 5);
      const trajectoryDelta = (recentAccuracy != null && priorAccuracy != null) ? recentAccuracy - priorAccuracy : null;
      return {
        id, correct, total, accuracy: total ? correct / total : 0,
        trajectoryDelta, isDecaying: trajectoryDelta != null && trajectoryDelta <= -this.decayDelta,
      };
    }).filter(Boolean).sort((a, b) => b.total - a.total);
  },

  /** Domains strong (>=strongThreshold) 6-11 months ago that have since dropped
   * by >=decayDelta in the last 6 months — both windows honest about sample
   * size — the Decay radar's "shore it up" list. */
  decayRadar() {
    const rows = atlasRows();
    return PROGRESS.domains.map((id) => {
      const mine = rows.filter((r) => r.categoryID === id);
      const past = atlasQuarterAccuracy(mine, 6, 11);
      const recent = atlasQuarterAccuracy(mine, 0, 5);
      if (past == null || recent == null || past < this.strongThreshold || recent > past - this.decayDelta) return null;
      return { id, pastAccuracy: past, recentAccuracy: recent, delta: recent - past };
    }).filter(Boolean).sort((a, b) => a.delta - b.delta);
  },

  /** A genuine strongest + weakest domain for the non-member teaser
   * (MONETIZATION §4a: "a real preview, never a nag"). null until the player
   * has enough history for at least one honest read. */
  previewLine() {
    const ds = this.domains().filter((d) => d.total >= 3).sort((a, b) => a.accuracy - b.accuracy);
    if (!ds.length) return null;
    const weakest = ds[0], strongest = ds[ds.length - 1];
    const wPct = Math.round(weakest.accuracy * 100), wName = catById(weakest.id).name;
    if (strongest.id === weakest.id) {
      return `${wPct}% in ${wName} so far — Club maps every domain across 12 months and shows what's rising or drifting.`;
    }
    const sPct = Math.round(strongest.accuracy * 100), sName = catById(strongest.id).name;
    return `${sPct}% in ${sName}, ${wPct}% in ${wName} — Club maps everything you know and where it's drifting.`;
  },
};

// Tidbits Club EXCLUSIVE — Expedition (docs/CLUB-FEATURES-BUILD.md "Feature 5").
// A multi-week structured CAMPAIGN through one domain: an ordered list of
// STAGES, each a normal category+difficulty-band round the EXISTING engine
// already plays (routed into 'classic' via Expeditions.startStage) — NOT a
// new game engine, same discipline as Weak-Spot/Marathon. The taxonomy
// (CATEGORIES) is FLAT — no sub-domains like "1920s" or "South America" — so
// stages within one campaign differentiate by DIFFICULTY BAND, the same
// constraint Knowledge Atlas hit. Mirrors the Apple reference
// (Core/Models/ExpeditionModels.swift + Core/Store/Expeditions.swift)
// byte-for-byte in campaign content; several campaigns may be in progress at
// once (unlike Marathon's at-most-one run), so persistence is a MAP keyed by
// expeditionId, not a singleton.
const EXPEDITION_PROGRESS_KEY = 'tidbits.expeditionProgress';
const EXPEDITION_CERTS_KEY = 'tidbits.expeditionCertificates';

export const Expeditions = {
  // 3 hand-defined 7-stage campaigns (design spec: "start with 2–3"; the
  // shape allows adding more later — append here, no other client change
  // needed). categoryId is a real web CATEGORIES id.
  all: [
    {
      id: 'twentieth-century', title: 'The 20th Century', symbol: '📜', domain: 'history',
      subtitle: 'A hundred years, decade by decade — from the Great War to the dot-com boom.',
      stages: [
        { index: 0, title: 'Turn of the Century', blurb: 'Where it all began — the basics of a hundred years.', categoryId: 'history', difficultyRange: [1, 2], questionCount: 10, passBar: 6 },
        { index: 1, title: 'The Great Wars', blurb: 'Two wars that reshaped the century.', categoryId: 'history', difficultyRange: [1, 3], questionCount: 10, passBar: 6 },
        { index: 2, title: 'The Cold War Era', blurb: 'A world split in two.', categoryId: 'history', difficultyRange: [2, 3], questionCount: 10, passBar: 6 },
        { index: 3, title: 'Movements & Milestones', blurb: 'Civil rights, independence, revolutions.', categoryId: 'history', difficultyRange: [2, 4], questionCount: 10, passBar: 6 },
        { index: 4, title: 'Leaders & Turning Points', blurb: 'The decisions that moved history.', categoryId: 'history', difficultyRange: [3, 4], questionCount: 10, passBar: 6 },
        { index: 5, title: 'The Wider Century', blurb: 'Everything else the timeline holds.', categoryId: 'history', difficultyRange: [3, 5], questionCount: 10, passBar: 6 },
        { index: 6, title: "The Historian's Final Exam", blurb: "The century's hardest corners.", categoryId: 'history', difficultyRange: [4, 5], questionCount: 10, passBar: 6 },
      ],
    },
    {
      id: 'around-the-world', title: 'Around the World', symbol: '🌎', domain: 'geography',
      subtitle: 'A geography trek from the basics of the map to its far corners.',
      stages: [
        { index: 0, title: 'The Basics of the Map', blurb: 'Continents, oceans, and the big picture.', categoryId: 'geography', difficultyRange: [1, 2], questionCount: 10, passBar: 6 },
        { index: 1, title: 'Capitals & Borders', blurb: 'Where the lines are drawn.', categoryId: 'geography', difficultyRange: [1, 3], questionCount: 10, passBar: 6 },
        { index: 2, title: 'Rivers, Ranges & Deserts', blurb: "The planet's physical geography.", categoryId: 'geography', difficultyRange: [2, 3], questionCount: 10, passBar: 6 },
        { index: 3, title: 'Nations & Peoples', blurb: 'Who lives where, and why.', categoryId: 'geography', difficultyRange: [2, 4], questionCount: 10, passBar: 6 },
        { index: 4, title: 'Cities of the World', blurb: "The places everyone's heard of.", categoryId: 'geography', difficultyRange: [3, 4], questionCount: 10, passBar: 6 },
        { index: 5, title: 'The Far Corners', blurb: "The places most people haven't.", categoryId: 'geography', difficultyRange: [3, 5], questionCount: 10, passBar: 6 },
        { index: 6, title: 'World-Class', blurb: "Geography's hardest questions.", categoryId: 'geography', difficultyRange: [4, 5], questionCount: 10, passBar: 6 },
      ],
    },
    {
      id: 'scientific-record', title: 'The Scientific Record', symbol: '⚛️', domain: 'science',
      subtitle: 'From first principles to the frontier — the story of how we know what we know.',
      stages: [
        { index: 0, title: 'First Principles', blurb: 'The fundamentals everyone starts with.', categoryId: 'science', difficultyRange: [1, 2], questionCount: 10, passBar: 6 },
        { index: 1, title: 'Matter & Energy', blurb: 'Physics and chemistry, from the ground up.', categoryId: 'science', difficultyRange: [1, 3], questionCount: 10, passBar: 6 },
        { index: 2, title: 'Life Itself', blurb: "Biology's big ideas.", categoryId: 'science', difficultyRange: [2, 3], questionCount: 10, passBar: 6 },
        { index: 3, title: 'The Great Discoveries', blurb: 'The breakthroughs that changed everything.', categoryId: 'science', difficultyRange: [2, 4], questionCount: 10, passBar: 6 },
        { index: 4, title: 'The Scientists Behind It', blurb: 'The people who did the work.', categoryId: 'science', difficultyRange: [3, 4], questionCount: 10, passBar: 6 },
        { index: 5, title: 'The Frontier', blurb: 'Where the science is still being written.', categoryId: 'science', difficultyRange: [3, 5], questionCount: 10, passBar: 6 },
        { index: 6, title: 'The Comprehensive Exam', blurb: "Science's deepest cuts.", categoryId: 'science', difficultyRange: [4, 5], questionCount: 10, passBar: 6 },
      ],
    },
  ],

  named(id) { return this.all.find((e) => e.id === id) || null; },
  stage(expedition, stageIndex) { return (expedition && expedition.stages.find((s) => s.index === stageIndex)) || null; },

  /** Every campaign's progress, keyed by expeditionId — several may be in
   * progress at once (unlike Marathon's at-most-one run). */
  _progressAll() { return LS.get(EXPEDITION_PROGRESS_KEY, {}); },
  progress(id) { return this._progressAll()[id] || null; },
  available() { return this.all.map((expedition) => ({ expedition, progress: this.progress(expedition.id) })); },

  /** The question set for one stage — a fresh, difficulty-banded pull from the
   * bundled corpus each attempt (a stage is replayable on a miss, so there's
   * no "seen" exclusion the way a normal round has). Never-empty: relaxes to
   * the whole category pool if the difficulty band comes up thin. `pull`
   * mirrors Corpus.pull's signature (categoryId, seenSet, limit) — the caller
   * passes it in so Store stays framework-free of the corpus loader (same
   * pattern as WeakSpotArena.build / Marathon.startNew). */
  startStage(expeditionOrId, stageIndex, pull) {
    const expedition = typeof expeditionOrId === 'string' ? this.named(expeditionOrId) : expeditionOrId;
    const stage = this.stage(expedition, stageIndex);
    if (!expedition || !stage || typeof pull !== 'function') return [];
    const overfetch = Math.max(stage.questionCount * 8, 80);
    const pool = pull(stage.categoryId, new Set(), overfetch) || [];
    const [lo, hi] = stage.difficultyRange;
    let banded = pool.filter((q) => (q.difficulty || 1) >= lo && (q.difficulty || 1) <= hi);
    if (banded.length < stage.questionCount) banded = pool;
    return banded.slice(0, stage.questionCount);
  },

  /** A stage just finished — pass advances (and unlocks the next stage); the
   * LAST stage passing writes the permanent certificate and clears the
   * in-progress row (mirrors Marathon's finish). Fail leaves progress exactly
   * where it was — the player stays on the same stage, "try again." */
  recordStageResult(expeditionId, stageIndex, correct, total) {
    const expedition = this.named(expeditionId);
    const stage = this.stage(expedition, stageIndex);
    if (!expedition || !stage) return { passed: false, certificate: null };
    const all = this._progressAll();
    const p = all[expeditionId] || { currentStageIndex: 0, stageResults: [], startedAt: Date.now(), lastPlayedAt: Date.now() };
    const passed = correct >= stage.passBar;
    p.stageResults = p.stageResults.filter((r) => r.stage !== stageIndex);
    p.stageResults.push({ stage: stageIndex, pass: passed, score: correct, total });
    p.lastPlayedAt = Date.now();
    if (passed) p.currentStageIndex = Math.max(p.currentStageIndex, stageIndex + 1);
    if (!passed || stageIndex < expedition.stages.length - 1) {
      all[expeditionId] = p;
      LS.set(EXPEDITION_PROGRESS_KEY, all);
      return { passed, certificate: null };
    }
    // Final stage passed — write the certificate, retire the progress row.
    const totalScore = p.stageResults.reduce((s, r) => s + r.score, 0);
    const certificate = { expeditionId, domain: expedition.domain, title: expedition.title, completedAt: Date.now(), totalScore, stagesCompleted: expedition.stages.length };
    const certs = this.certificates();
    certs.unshift(certificate);
    LS.set(EXPEDITION_CERTS_KEY, certs);
    delete all[expeditionId];
    LS.set(EXPEDITION_PROGRESS_KEY, all);
    return { passed: true, certificate };
  },

  /** Every completed Expedition, most recent first — the permanent history
   * (the hub's Completed/certificates shelf). */
  certificates() { return LS.get(EXPEDITION_CERTS_KEY, []); },

  /** Expeditions are curated CONTENT, not player data (unlike Weak-Spot/Story
   * Archive, which are built from ordinary free play) — so the non-member
   * pitch is the same honest description everyone sees, never a nag
   * (MONETIZATION §4a). Both the hub list and an expedition's map are a REAL
   * preview reachable by everyone; only tapping Play on a stage is gated. */
  previewLine() {
    return 'Multi-week campaigns through a single subject — pick one, and go at your own pace.';
  },
};
