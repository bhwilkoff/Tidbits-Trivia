// Tidbits — domain config + local persistence (web). Mirrors the Apple
// TriviaCategory / GameMode / RecordsStore. Records + streak live in
// localStorage (the per-ecosystem sync island; sign-in sync is later).

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
export const catById = (id) => CATEGORIES.find((c) => c.id === id) || CATEGORIES[0];

export const MODES = {
  classic: { id: 'classic', title: 'Classic', blurb: 'Ten questions. Speed counts.', perQuestion: 20, count: 10, accent: '#2D5BFF' },
  timeAttack: { id: 'timeAttack', title: 'Time Attack', blurb: 'How many in 60 seconds?', perQuestion: null, globalClock: 60, count: 25, accent: '#FF5C5C' },
  survival: { id: 'survival', title: 'Survival', blurb: 'One wrong answer ends it.', perQuestion: 15, count: 99, accent: '#8B5CF6' },
  daily: { id: 'daily', title: 'Daily Tidbit', blurb: 'Everyone’s puzzle. Keep your streak.', perQuestion: 30, count: 7, accent: '#FFC93C' },
};

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
  addRecord(rec) {
    const all = this.records();
    all.unshift(rec);
    LS.set('tidbits.records', all.slice(0, 500));
    if (rec.mode === 'daily') this._bumpStreak();
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

  // Missed facts for spaced review.
  missed() { return LS.get('tidbits.missed', []); },
  recordMisses(answered) {
    const missed = this.missed();
    const byId = new Map(missed.map((m) => [m.id, m]));
    for (const a of answered) {
      if (a.correct) { const m = byId.get(a.q.id); if (m) m.resolved = true; }
      else {
        const ex = byId.get(a.q.id);
        if (ex) { ex.missCount++; ex.resolved = false; }
        else { const m = { id: a.q.id, q: a.q, missCount: 1, resolved: false }; missed.push(m); byId.set(a.q.id, m); }
      }
    }
    LS.set('tidbits.missed', missed);
  },
  dueReview(limit = 2) {
    return this.missed().filter((m) => !m.resolved).sort((a, b) => b.missCount - a.missCount).slice(0, limit).map((m) => m.q);
  },
  resetAll() {
    ['tidbits.records', 'tidbits.streak', 'tidbits.missed', 'tidbits.seen'].forEach((k) => localStorage.removeItem(k));
    this._seen.clear();
  },
};
