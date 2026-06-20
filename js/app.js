// Tidbits — web app shell: router, views, and the game loop. Mirrors the
// Apple AppStore + GameEngine + views. Vanilla JS, no framework, no build.

import { Corpus, Wikipedia } from './api.js';
import { Store, CATEGORIES, catColor, catById, MODES, STAKE_BUDGET, dayKey, APP_STORES } from './store.js';
import { Scoring } from './engine.js';

const $ = (sel, root = document) => root.querySelector(sel);
const h = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const app = $('#app');
let game = null;

// ---------------- Router (hash → tab) ----------------
const TABS = ['play', 'create', 'records'];
function currentTab() {
  const t = (location.hash.replace('#/', '') || 'play').split('?')[0];
  return TABS.includes(t) ? t : 'play';
}
window.addEventListener('hashchange', render);

async function boot() {
  renderLoading('Loading Tidbits…');
  try { await Corpus.load(); } catch (e) { /* live fallback still works */ }
  if (!location.hash) location.hash = '#/play';
  if (location.hash.startsWith('#/daily')) { render(); startGame('daily', catById('mixed')); return; }
  render();
}

// ---------------- Top-level render ----------------
function render() {
  if (game) return; // game overlay owns the screen
  const tab = currentTab();
  app.innerHTML = `
    ${header(tab)}
    <main class="main">${tab === 'play' ? viewHome() : tab === 'create' ? viewCreate() : viewRecords()}</main>`;
  if (tab === 'play') bindHome();
  if (tab === 'create') bindCreate();
  document.title = 'Tidbits Trivia';
}

function header(tab) {
  const tabBtn = (id, label, icon) => `<a class="tab ${tab === id ? 'active' : ''}" href="#/${id}">${icon}<span>${label}</span></a>`;
  return `<header class="topbar">
    <div class="brand">TIDBITS</div>
    <nav class="tabs">
      ${tabBtn('play', 'Play', '▶')}
      ${tabBtn('create', 'Create', '✦')}
      ${tabBtn('records', 'Records', '▌▌')}
    </nav>
  </header>`;
}

function renderLoading(msg) {
  app.innerHTML = `<div class="center-screen"><div class="spinner"></div><p class="muted">${h(msg)}</p></div>`;
}

// ---------------- Home ----------------
function viewHome() {
  const cats = CATEGORIES.map((c) => `
    <button class="cat-card card" data-cat="${c.id}">
      <span class="cat-icon" style="background:${catColor(c)}">${c.symbol}</span>
      <span class="cat-name">${h(c.name)}</span>
      <span class="cat-blurb muted">${h(c.blurb)}</span>
    </button>`).join('');
  const modes = ['classic', 'timeAttack', 'survival', 'stake', 'sweep'].map((m) =>
    `<button class="chip" data-mode="${m}">${h(MODES[m].title)}</button>`).join('');
  return `
    <h1 class="page-title">Trivia from the whole of Wikipedia.</h1>
    <button class="banner card daily" data-daily><div><div class="banner-title">DAILY TIDBIT</div>
      <div class="muted">7 questions. Everyone gets the same set. Keep your streak.</div></div><span class="chev">›</span></button>
    <h2 class="section">Pick a mode</h2>
    <div class="chips" id="modes">${modes}</div>
    <h2 class="section">Choose a category</h2>
    <div class="cat-grid">${cats}</div>
    ${appsPromo()}`;
}

// Native-app promotion — appears at the foot of the scrollable home screen.
// Store links flip on per-platform as each app ships (APP_STORES in store.js).
function appsPromo() {
  const card = (s) => s.url
    ? `<a class="store-btn" href="${s.url}" target="_blank" rel="noopener"><b>${h(s.label)}</b><span class="muted">${h(s.sub)}</span></a>`
    : `<div class="store-btn soon" aria-disabled="true"><b>${h(s.label)}</b><span class="muted">${h(s.sub)} · soon</span></div>`;
  return `<section class="apps-promo">
      <h2 class="section">Get Tidbits everywhere</h2>
      <p class="muted">Same trivia, native on every screen — play online here anytime.</p>
      <div class="store-row">${APP_STORES.map(card).join('')}</div>
      <p class="apps-foot muted"><a href="/support.html">Support</a> · <a href="/privacy.html">Privacy</a> · tidbitstrivia.com</p>
    </section>`;
}

let selectedMode = 'classic';
function bindHome() {
  $('#modes').addEventListener('click', (e) => {
    const b = e.target.closest('[data-mode]'); if (!b) return;
    selectedMode = b.dataset.mode;
    [...$('#modes').children].forEach((c) => c.classList.toggle('on', c.dataset.mode === selectedMode));
  });
  [...$('#modes').children].forEach((c) => c.classList.toggle('on', c.dataset.mode === selectedMode));
  $('[data-daily]').addEventListener('click', () => startGame('daily', catById('mixed')));
  app.querySelectorAll('[data-cat]').forEach((b) =>
    b.addEventListener('click', () => startGame(selectedMode, catById(b.dataset.cat))));
}

// ---------------- Create ----------------
function viewCreate() {
  const sugg = ['Space exploration', 'Ancient Rome', 'Jazz', 'Volcanoes', 'The Olympics', 'Marie Curie'];
  return `
    <h1 class="page-title">Create a quiz</h1>
    <p class="muted">Pick any subject. We'll pull it straight from Wikipedia and build you a quiz.</p>
    <div class="card pad">
      <input id="topic" class="input" placeholder="e.g. The Renaissance" autocomplete="off">
      <button id="gen" class="btn btn-grape btn-full">Generate Quiz</button>
      <div id="create-err" class="error" hidden></div>
    </div>
    <h2 class="section">Need a spark?</h2>
    <div class="chips wrap">${sugg.map((s) => `<button class="chip" data-sugg="${h(s)}">${h(s)}</button>`).join('')}</div>`;
}
function bindCreate() {
  const run = async () => {
    const topic = $('#topic').value.trim();
    if (topic.length < 2) return;
    const err = $('#create-err'); err.hidden = true;
    const btn = $('#gen'); btn.textContent = 'Building your quiz…'; btn.disabled = true;
    try {
      const qs = await Wikipedia.generate(topic, 'mixed', 8);
      if (qs.length >= 3) startGame('classic', catById('mixed'), { custom: qs, label: topic });
      else { err.textContent = `Couldn't build a good quiz for “${topic}”. Try a broader or more famous subject.`; err.hidden = false; }
    } catch { err.textContent = 'Network trouble reaching Wikipedia. Try again.'; err.hidden = false; }
    btn.textContent = 'Generate Quiz'; btn.disabled = false;
  };
  $('#gen').addEventListener('click', run);
  $('#topic').addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
  app.querySelectorAll('[data-sugg]').forEach((b) =>
    b.addEventListener('click', () => { $('#topic').value = b.dataset.sugg; run(); }));
}

// ---------------- Records ----------------
function viewRecords() {
  const recs = Store.records();
  if (!recs.length) return `<h1 class="page-title">Records</h1><div class="empty card pad"><p>No games yet.</p><p class="muted">Play a round and your scores, streaks, and facts to review show up here.</p></div>`;
  const lt = Store.lifetime(), st = Store.streak();
  const bests = Object.values(MODES).map((m) => ({ m, best: Store.bestScore(m.id) })).filter((x) => x.best > 0);
  const review = Store.dueReview(8);
  return `
    <h1 class="page-title">Records</h1>
    <div class="banner card daily"><div><div class="muted">DAILY STREAK</div><div class="big">${st.current} days</div></div><div class="muted">best ${st.best} 🔥</div></div>
    <div class="stat-row">
      ${statBox(lt.games, 'Games', '#8B5CF6')}${statBox(lt.acc + '%', 'Lifetime acc.', '#2D5BFF')}${statBox(lt.correct, 'Right', '#2FCB8A')}
    </div>
    ${progressSection()}
    ${calibrationSection()}
    <h2 class="section">Personal bests</h2>
    ${bests.map((x) => `<div class="card row"><b>${h(x.m.title)}</b><span class="big-sm">${x.best}</span></div>`).join('') || '<p class="muted">Play a mode to set a best.</p>'}
    ${review.length ? `<h2 class="section">Facts to review</h2><p class="muted">We slip these back into future games.</p>
      ${review.map((q) => `<div class="card pad"><b>${h(q.prompt)}</b><div class="ans">Answer: ${h(q.options[q.correctIndex])}</div></div>`).join('')}` : ''}`;
}
const statBox = (v, l, c) => `<div class="stat card" style="--tint:${c}"><div class="stat-v">${v}</div><div class="stat-l">${l}</div></div>`;

// F1 calibration — per-tier hit rate from Stake rounds.
function calibrationSection() {
  const c = Store.calibration();
  const tiers = STAKE_BUDGET.filter((t) => c[t.value] && c[t.value].total > 0);
  if (!tiers.length) return '';
  const rows = tiers.map((t) => {
    const o = c[t.value], pct = Math.round((o.hits / o.total) * 100);
    return `<div class="card calib-row">
      <span class="calib-label">${h(t.label)}</span>
      <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, (o.hits / o.total) * 100)}%;background:var(--color-mint)"></div></div>
      <span class="calib-meta">${o.hits}/${o.total} · ${pct}%</span></div>`;
  }).join('');
  return `<h2 class="section">Your calibration</h2>
    <p class="muted">From Stake rounds: how often each confidence level actually landed. Well-calibrated means your hit-rate climbs with your confidence.</p>
    ${rows}`;
}

// Topic Levels (depth) + The Pie (breadth) — SOLO-BACKLOG M3 + M4.
function progressSection() {
  const ds = Store.progress();
  const earned = ds.filter((d) => d.hasWedge).length;
  const seg = 100 / ds.length;
  const stops = ds.map((d, i) => {
    const col = d.hasWedge ? catColor(catById(d.id)) : '#e8dcc2';
    return `${col} ${(i * seg).toFixed(2)}% ${((i + 1) * seg).toFixed(2)}%`;
  }).join(', ');
  const blurb = earned === 7
    ? 'Full pie — every domain mastered. That breadth is yours to keep.'
    : 'Earn a wedge in each domain by answering its questions well. The pie fills only when you cover them all.';
  const rows = ds.filter((d) => d.total > 0).map((d) => {
    const c = catById(d.id), col = catColor(c);
    return `<div class="card topic-row">
      <span class="topic-ic" style="background:${col}">${c.symbol}</span>
      <div class="topic-main">
        <div class="topic-head"><b>${h(c.name)}</b>${d.hasWedge ? '<span class="wedge">✓</span>' : ''}<span class="lvl" style="background:${col}">Lvl ${d.level}</span></div>
        <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, d.levelProgress * 100)}%;background:${col}"></div></div>
      </div></div>`;
  }).join('');
  return `<h2 class="section">Your knowledge</h2>
    <div class="card pie-card"><div class="pie" style="background:conic-gradient(${stops})"><span class="pie-count">${earned}/7</span></div><p class="muted pie-blurb">${blurb}</p></div>
    ${rows}`;
}

// ---------------- Game engine ----------------
class Game {
  constructor(mode, category, opts = {}) {
    this.mode = MODES[mode]; this.category = category; this.label = opts.label;
    this.questions = []; this.index = 0; this.score = 0; this.streak = 0; this.maxStreak = 0;
    this.answered = []; this.chosen = null; this.phase = 'loading';
    this.remaining = 0; this.timer = null; this.qStart = 0; this.globalDeadline = null;
    this._custom = opts.custom;
    // Stake: the remaining confidence-chip budget + the chip on this question (0 = unset).
    this.stakeTiers = this.mode.id === 'stake' ? STAKE_BUDGET.map((t) => ({ value: t.value, label: t.label, remaining: t.count })) : [];
    this.currentStake = 0;
    this.stakeOutcomes = {}; // F1 calibration: tierValue -> {hits, total}
  }
  async load() {
    let qs;
    if (this._custom) qs = this._custom;
    else if (this.mode.id === 'daily') qs = Corpus.daily(dayKey(), 7);
    else {
      qs = Corpus.pull(this.category.id, Store._seen, this.mode.count);
      if (qs.length < this.mode.count) {
        const topic = this.category.id === 'mixed' ? 'popular' : this.category.name;
        const live = await Wikipedia.generate(topic, this.category.id, this.mode.count - qs.length);
        qs = qs.concat(live);
      }
      // Spaced-repetition review: in a single-category game, only re-ask misses
      // from THAT category — otherwise a missed Film & TV question gets woven
      // into an Arts & Lit round and shows the wrong category badge.
      let review = Store.dueReview(30);
      if (this.category.id !== 'mixed') review = review.filter((q) => q.categoryID === this.category.id);
      qs = this._weave(qs, review.slice(0, 2));
    }
    this.questions = (this.mode.count === 99 ? qs : qs.slice(0, this.mode.count));
    Store.markSeen(this.questions.map((q) => q.id));
    if (!this.questions.length) { this.phase = 'error'; return; }
    if (this.mode.globalClock) this.globalDeadline = Date.now() + this.mode.globalClock * 1000;
    this._begin();
  }
  _weave(fresh, review) {
    const ids = new Set(fresh.map((q) => q.id));
    const inject = review.filter((q) => !ids.has(q.id)).slice(0, Math.max(1, Math.floor(fresh.length / 4)));
    if (!inject.length || fresh.length <= inject.length) return fresh;
    const r = fresh.slice();
    inject.forEach((q, i) => { r[Math.min(r.length - 1, Math.floor((i + 1) * r.length / (inject.length + 1)))] = q; });
    return r;
  }
  get current() { return this.questions[this.index]; }
  setStake(value) {
    if (this.mode.id !== 'stake' || this.phase !== 'playing') return;
    const tier = this.stakeTiers.find((t) => t.value === value);
    if (!tier || tier.remaining <= 0) return;
    if (this.currentStake !== 0) { const prev = this.stakeTiers.find((t) => t.value === this.currentStake); if (prev) prev.remaining++; }
    tier.remaining--; this.currentStake = value;
    renderGame();
  }
  get stakeLabel() { return this.stakeTiers.find((t) => t.value === this.currentStake)?.label ?? ''; }
  _begin() {
    this.chosen = null; this.currentStake = 0; this.phase = 'playing'; this.qStart = Date.now();
    this.budget = this._globalRemaining() ?? this.mode.perQuestion ?? 30;
    this.remaining = this.budget;
    clearInterval(this.timer);
    this.timer = setInterval(() => this._tick(), 100);
    renderGame();
  }
  _globalRemaining() { return this.globalDeadline ? Math.max(0, (this.globalDeadline - Date.now()) / 1000) : null; }
  _tick() {
    if (this.phase !== 'playing') return;
    const g = this._globalRemaining();
    if (g !== null) { this.remaining = g; if (g <= 0) return this._end(); }
    else { this.remaining = Math.max(0, this.budget - (Date.now() - this.qStart) / 1000); if (this.remaining <= 0) return this.submit(null); }
    updateClock();
  }
  submit(choice) {
    if (this.phase !== 'playing') return;
    // Stake: a chip must be committed before a manual answer (a timeout, choice === null, still resolves).
    if (this.mode.id === 'stake' && this.currentStake === 0 && choice !== null) return;
    clearInterval(this.timer);
    this.chosen = choice;
    const q = this.current, taken = (Date.now() - this.qStart) / 1000;
    const correct = choice === q.correctIndex;
    this.answered.push({ q, chosen: choice, correct, taken });
    if (this.mode.id === 'stake' && this.currentStake !== 0) {
      const o = this.stakeOutcomes[this.currentStake] || { hits: 0, total: 0 };
      o.total++; if (correct) o.hits++;
      this.stakeOutcomes[this.currentStake] = o;
    }
    if (correct) {
      this.streak++; this.maxStreak = Math.max(this.maxStreak, this.streak);
      // Stake: the reward IS the chip (calibration). Sweep: +1 per correct — the
      // score is the count of the set you filled (no speed bonus). Else speed-aware.
      this.score += this.mode.id === 'stake' ? this.currentStake
        : this.mode.id === 'sweep' ? 1
        : Scoring.points(true, taken, this.mode.perQuestion ?? this.budget, this.streak);
    } else { this.streak = 0; }
    this.phase = 'reveal';
    renderGame();
  }
  advance() {
    if (this.mode.id === 'survival' && this.answered.length && !this.answered.at(-1).correct) return this._end();
    if ((this._globalRemaining() ?? 1) <= 0) return this._end();
    this.index++;
    if (this.index >= this.questions.length) return this._end();
    this._begin();
  }
  _end() { clearInterval(this.timer); this.phase = 'finished'; this._persist(); renderResults(); }
  _persist() {
    const correct = this.answered.filter((a) => a.correct).length;
    Store.addRecord({ mode: this.mode.id, categoryID: this.category.id, score: this.score, correct, total: this.answered.length, maxStreak: this.maxStreak, date: dayKey() });
    Store.recordMisses(this.answered);
    if (this.mode.id === 'stake') Store.addCalibration(this.stakeOutcomes);
  }
  summary() {
    const correct = this.answered.filter((a) => a.correct).length;
    return { correct, total: this.answered.length, score: this.score, maxStreak: this.maxStreak, answered: this.answered, acc: this.answered.length ? Math.round(correct / this.answered.length * 100) : 0 };
  }
}

async function startGame(mode, category, opts) {
  game = new Game(mode, category, opts);
  renderLoading('Pulling fresh tidbits…');
  await game.load();
  if (game.phase === 'error') renderGameError();
}

function quitGame() { if (game) clearInterval(game.timer); game = null; render(); }

// ---------------- Game render ----------------
function renderGame() {
  const q = game.current; if (!q) return;
  const cat = catById(q.categoryID);
  // Stake: answers are locked until a confidence chip is committed.
  const staking = game.mode.id === 'stake';
  const lockAnswers = game.phase === 'reveal' || (staking && game.currentStake === 0);
  const opts = q.options.map((o, i) => {
    let cls = 'opt';
    if (game.phase === 'reveal') {
      if (i === q.correctIndex) cls += ' correct';
      else if (i === game.chosen) cls += ' wrong';
      else cls += ' dim';
    }
    return `<button class="${cls}" data-opt="${i}" ${lockAnswers ? 'disabled' : ''}>${h(o)}</button>`;
  }).join('');
  const stakeSel = (staking && game.phase === 'playing') ? stakeSelector() : '';
  const sweepGr = game.mode.id === 'sweep' ? sweepGrid() : '';
  const reveal = game.phase === 'reveal' ? revealCard(q) : '';
  const fixedCount = game.mode.id === 'classic' || game.mode.id === 'daily' || staking || game.mode.id === 'sweep';
  const progress = fixedCount ? `${game.index + 1} / ${game.questions.length}` : `#${game.index + 1}`;
  app.innerHTML = `
    <div class="game">
      <div class="hud">
        <button class="x" data-quit>✕</button>
        <span class="pill streak ${game.streak >= 2 ? 'hot' : ''}">🔥 ${game.streak}</span>
        <span class="pill score">★ ${game.score}</span>
      </div>
      <div class="clockbar"><span id="clk-label">${progress}</span><div class="clock-track"><div id="clk-fill" class="clock-fill"></div></div><span id="clk-secs"></span></div>
      <div class="qwrap">
        <div class="card qcard"><div class="qcat" style="color:${catColor(cat)}">${h(cat.name.toUpperCase())}</div><div class="qprompt">${h(q.prompt)}</div></div>
        ${sweepGr}
        ${stakeSel}
        <div class="opts">${opts}</div>
        ${reveal}
      </div>
      ${game.phase === 'reveal' ? `<button class="btn btn-ink btn-full" data-next>${isLast() ? 'See Results' : 'Next'}</button>` : ''}
    </div>`;
  $('[data-quit]').addEventListener('click', quitGame);
  if (game.phase === 'playing' && !lockAnswers) app.querySelectorAll('[data-opt]').forEach((b) => b.addEventListener('click', () => game.submit(+b.dataset.opt)));
  app.querySelectorAll('[data-stake]').forEach((b) => b.addEventListener('click', () => game.setStake(+b.dataset.stake)));
  if (game.phase === 'reveal') $('[data-next]').addEventListener('click', () => game.advance());
  updateClock();
}
function isLast() { return (game.mode.id === 'classic' || game.mode.id === 'daily' || game.mode.id === 'stake' || game.mode.id === 'sweep') && game.index + 1 >= game.questions.length; }
// Sweep's persistent fill-grid — one cell per question, filled green (hit) /
// coral (miss) as you go; the current cell is ringed. The grid is the scoreboard.
function sweepGrid() {
  const cells = game.questions.map((_, i) => {
    const a = game.answered[i];
    const cls = a ? (a.correct ? 'hit' : 'miss') : (i === game.index ? 'now' : '');
    return `<span class="sweep-cell ${cls}"></span>`;
  }).join('');
  return `<div class="card sweep-card"><div class="sweep-head">Set: ${game.score} / ${game.questions.length}</div><div class="sweep-grid">${cells}</div></div>`;
}
function stakeSelector() {
  const head = game.currentStake === 0 ? 'How sure are you?' : `Staked: ${h(game.stakeLabel)}`;
  const chips = game.stakeTiers.map((t) => {
    const sel = game.currentStake === t.value ? ' sel' : '';
    const off = (t.remaining === 0 && game.currentStake !== t.value) ? ' disabled' : '';
    return `<button class="stake-chip${sel}" data-stake="${t.value}"${off ? ' disabled' : ''}>
      <span class="stake-label">${h(t.label)}</span><span class="stake-meta">+${t.value} · ${t.remaining} left</span></button>`;
  }).join('');
  return `<div class="card stake-card"><div class="stake-head">${head}</div><div class="stake-chips">${chips}</div></div>`;
}
function revealCard(q) {
  const correct = game.answered.at(-1)?.correct;
  const stakeTag = game.mode.id === 'stake' ? `<span class="stake-earned${correct ? ' hit' : ''}">${correct ? '+' + game.currentStake : '+0'}</span>` : '';
  return `<div class="card reveal"><div class="reveal-h">${correct ? '✅ Nice — you knew it.' : '💡 Now you know.'}${stakeTag}</div>
    <p>${h(q.explanation)}</p>${q.sourceURL ? `<a href="${h(q.sourceURL)}" target="_blank" rel="noopener" class="link">Read ${h(q.sourceTitle)} on Wikipedia ↗</a>` : ''}</div>`;
}
function updateClock() {
  if (!game || game.phase !== 'playing') { const s = $('#clk-secs'); if (s) s.textContent = ''; return; }
  const frac = Math.max(0, Math.min(1, game.remaining / game.budget));
  const fill = $('#clk-fill'); if (fill) { fill.style.width = (frac * 100) + '%'; fill.classList.toggle('urgent', game.remaining <= 5); }
  const secs = $('#clk-secs'); if (secs) secs.textContent = Math.ceil(game.remaining) + 's';
}
function renderGameError() {
  app.innerHTML = `<div class="center-screen"><h2>No questions yet</h2><p class="muted">We couldn't reach Wikipedia and the corpus is empty.</p><button class="btn btn-primary" data-back>Back</button></div>`;
  $('[data-back]').addEventListener('click', quitGame);
}

// ---------------- Results ----------------
function renderResults() {
  const s = game.summary();
  const grid = s.answered.map((a) => (a.chosen === null ? '⬛' : a.correct ? '🟩' : '🟥')).join('');
  const headline = s.acc === 100 ? 'Flawless!' : s.acc >= 80 ? 'Brilliant' : s.acc >= 50 ? 'Nicely done' : 'Good run';
  const missed = s.answered.filter((a) => !a.correct);
  app.innerHTML = `
    <div class="results">
      <div class="card scorecard" style="--tint:${catColor(game.category)}">
        <div class="muted">${h(headline.toUpperCase())}</div><div class="huge">${s.score}</div>
        <div class="muted">${h(game.label || game.mode.title)} · ${h(game.category.name)}</div></div>
      <div class="stat-row">${statBox(s.correct + '/' + s.total, 'Correct', '#2FCB8A')}${statBox(s.acc + '%', 'Accuracy', '#2D5BFF')}${statBox(s.maxStreak, 'Best streak', '#FF5C5C')}</div>
      <div class="card pad grid-card"><div class="emoji">${grid}</div><div class="muted">Spoiler-free — safe to share</div></div>
      ${missed.length ? `<h2 class="section">Tidbits to remember</h2>${missed.map((a) => `<div class="card pad"><b>${h(a.q.prompt)}</b><div class="ans">Answer: ${h(a.q.options[a.q.correctIndex])}</div><p class="muted">${h(a.q.explanation)}</p></div>`).join('')}` : ''}
      <button class="btn btn-blue btn-full" data-share>Share Score</button>
      <button class="btn btn-primary btn-full" data-again>Play Again</button>
      <button class="btn btn-text btn-full" data-done>Done</button>
    </div>`;
  $('[data-share]').addEventListener('click', () => shareResult(s, grid));
  $('[data-again]').addEventListener('click', () => startGame(game.mode.id, game.category, game._custom ? { custom: game._custom, label: game.label } : undefined));
  $('[data-done]').addEventListener('click', quitGame);
}
async function shareResult(s, grid) {
  const header = game.mode.id === 'daily' ? `🧠 Tidbits Daily — ${dayKey()}` : `🧠 Tidbits Trivia — ${game.mode.title}`;
  const text = `${header}\n${grid}\n${s.correct}/${s.total} right · ${s.score} pts · ${s.acc}%\nTrivia from all of Wikipedia. Can you beat it?\n${location.origin}${location.pathname}`;
  try { if (navigator.share) { await navigator.share({ text }); return; } } catch {}
  try { await navigator.clipboard.writeText(text); toast('Copied to clipboard!'); } catch { toast('Copy failed'); }
}
function toast(msg) {
  const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg; document.body.appendChild(t);
  setTimeout(() => t.remove(), 1800);
}

boot();
