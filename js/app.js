// Tidbits — web app shell: router, views, and the game loop. Mirrors the
// Apple AppStore + GameEngine + views. Vanilla JS, no framework, no build.

import { Corpus, Pictures, ThisOrThat, ClosestCall, Ordering, Matching, TypeAnswer, OddOneOut, Enumerate, Difficulty, matchesAccepted, Wikipedia } from './api.js';
import { Store, CATEGORIES, catColor, catById, MODES, NIGHT, STAKE_BUDGET, dayKey, APP_STORES, SITE_URL } from './store.js';
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
  // Shareable Trivia Night deep links: #/night (Pub) or #/night/quick|works.
  if (location.hash.startsWith('#/night')) {
    render();
    const key = location.hash.split('/')[2] || 'pub';
    const idx = { quick: 0, pub: 1, works: 2 }[key] ?? 1;
    startGame('barTrivia', catById('mixed'), { nightPlan: { rounds: NIGHT.presets[idx].rounds }, label: NIGHT.presets[idx].name });
    return;
  }
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
  const rt = document.getElementById('review-toggle');
  if (rt) rt.addEventListener('change', (e) => Store.setReviewEnabled(e.target.checked));
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

// ---------------- Home (rule R-HOME-1: one Quick Play hero) ----------------
const ALL_MODES = ['classic', 'timeAttack', 'survival', 'stake', 'sweep', 'pictureId', 'thisOrThat', 'closestCall', 'ordering', 'matching', 'typeAnswer', 'oddOneOut', 'ladder'];
const CORE_MODES = ['classic', 'timeAttack', 'survival', 'stake'];

function quickPlayTarget() {
  const m = localStorage.getItem('tidbits.lastMode');
  const c = localStorage.getItem('tidbits.lastCat');
  if (m && MODES[m] && c) return { mode: m, cat: c };
  return { mode: 'classic', cat: 'mixed' };
}
function rememberPlay(mode, catId) {
  if (mode === 'daily') return;
  localStorage.setItem('tidbits.lastMode', mode);
  localStorage.setItem('tidbits.lastCat', catId);
}
function hasQuickPlayHistory() { return !!localStorage.getItem('tidbits.lastMode'); }
function getPresets() { try { return JSON.parse(localStorage.getItem('tidbits.presets') || '[]'); } catch { return []; } }
function savePreset(p) {
  const l = getPresets().filter((x) => x.name.toLowerCase() !== p.name.toLowerCase());
  l.unshift(p);
  localStorage.setItem('tidbits.presets', JSON.stringify(l.slice(0, 5)));
}

function viewHome() {
  const qp = quickPlayTarget();
  const qpMode = (MODES[qp.mode] || MODES.classic).title;
  const qpCat = (catById(qp.cat) || catById('mixed')).name;
  const first = !hasQuickPlayHistory();
  return `
    <h1 class="page-title">Trivia from the whole of Wikipedia.</h1>
    <button class="banner card hero" data-quickplay>
      <div class="hero-main">
        <div class="hero-title">▶ QUICK PLAY</div>
        <div class="hero-sub">${h(qpMode.toUpperCase())} · ${h(qpCat.toUpperCase())}</div>
        <div class="hero-hint">${first ? 'Tap to play — customize anytime' : 'Jump straight into a round'}</div>
      </div>
      <span class="hero-surprise" data-surprise role="button">🎲 Surprise</span>
    </button>
    <button class="banner card daily" data-daily><div><div class="banner-title">DAILY TIDBIT</div>
      <div class="muted">7 questions. Everyone gets the same set. Keep your streak.</div></div><span class="chev">›</span></button>
    <button class="banner card night-banner-cta" data-night-open><div><div class="banner-title">TRIVIA NIGHT</div>
      <div class="muted">Host or join a night of mixed rounds.</div></div><span class="chev">›</span></button>
    <button class="banner card customize-row" data-customize><div><div class="banner-title">Customize a game</div>
      <div class="muted">Pick a mode, a category, save a mix</div></div><span class="chev">›</span></button>
    <h2 class="section">More ways to play</h2>
    <div class="home-tiles">
      <a class="tile card" href="#/create"><span class="tile-emoji">✨</span><span class="tile-name">Create</span></a>
    </div>
    <dialog id="night-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Trivia Night</h2>
        <p class="muted">A night of mixed rounds — every kind of question. Each answer ends on a fact to learn.</p>
        <div class="night-presets">
          ${NIGHT.presets.map((p, i) => `<button type="button" class="night-preset${i === 1 ? ' on' : ''}" data-preset="${i}"><b>${h(p.name)}</b><span class="muted">${h(p.blurb)}</span></button>`).join('')}
        </div>
        <label class="night-cat-label">Category
          <select id="night-cat">${CATEGORIES.map((c) => `<option value="${c.id}">${h(c.name)}</option>`).join('')}</select>
        </label>
        <div class="night-actions">
          <button type="button" class="btn" data-night-cancel>Cancel</button>
          <button type="button" class="btn btn-primary" data-night-start>Start the Night</button>
        </div>
      </div>
    </dialog>
    <dialog id="customize-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Customize a game</h2>
        <h3 class="section">Mode</h3>
        <div class="chips" id="cust-modes"></div>
        <button type="button" class="link-btn" data-more-modes>More modes…</button>
        <h3 class="section">Category</h3>
        <div class="chips" id="cust-cats">
          ${CATEGORIES.map((c) => `<button type="button" class="chip" data-ccat="${c.id}">${h(c.name)}</button>`).join('')}
        </div>
        <div id="cust-presets"></div>
        <div class="night-actions">
          <button type="button" class="btn" data-cust-save>Save this</button>
          <button type="button" class="btn btn-primary" data-cust-start>Start</button>
        </div>
      </div>
    </dialog>
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

let custMode = 'classic';
let custCat = 'mixed';
let custShowAll = false;

function renderCustModes() {
  const list = custShowAll ? ALL_MODES : CORE_MODES;
  const box = $('#cust-modes');
  box.innerHTML = list.map((m) => `<button type="button" class="chip${m === custMode ? ' on' : ''}" data-cmode="${m}">${h(MODES[m].title)}</button>`).join('');
  box.querySelectorAll('[data-cmode]').forEach((b) => b.addEventListener('click', () => { custMode = b.dataset.cmode; renderCustModes(); }));
  const more = $('[data-more-modes]'); if (more) more.textContent = custShowAll ? 'Fewer modes' : 'More modes…';
}
function markCustCat() { $('#cust-cats').querySelectorAll('[data-ccat]').forEach((c) => c.classList.toggle('on', c.dataset.ccat === custCat)); }
function renderCustPresets() {
  const ps = getPresets();
  const el = $('#cust-presets');
  el.innerHTML = ps.length ? `<h3 class="section">★ My presets</h3><div class="chips">${ps.map((p, i) => `<button type="button" class="chip" data-preset-idx="${i}">${h(p.name)}</button>`).join('')}</div>` : '';
  el.querySelectorAll('[data-preset-idx]').forEach((b) => b.addEventListener('click', () => {
    const p = getPresets()[+b.dataset.presetIdx]; if (!p) return;
    custMode = p.mode; custCat = (p.categoryIds && p.categoryIds[0]) || 'mixed';
    renderCustModes(); markCustCat();
  }));
}

function bindHome() {
  // Quick Play — the ONE primary action (+ opt-in Surprise).
  $('[data-quickplay]').addEventListener('click', (e) => {
    if (e.target.closest('[data-surprise]')) return;
    const qp = quickPlayTarget(); rememberPlay(qp.mode, qp.cat); startGame(qp.mode, catById(qp.cat));
  });
  const surprise = $('[data-surprise]');
  if (surprise) surprise.addEventListener('click', (e) => {
    e.stopPropagation();
    const m = ALL_MODES[Math.floor(Math.random() * ALL_MODES.length)];
    const c = CATEGORIES[Math.floor(Math.random() * CATEGORIES.length)];
    rememberPlay(m, c.id); startGame(m, catById(c.id));
  });
  $('[data-daily]').addEventListener('click', () => startGame('daily', catById('mixed')));

  // Trivia Night dialog (native <dialog showModal> — focus trap + ESC free).
  let nightPreset = 1;
  const dlg = $('#night-dlg');
  $('[data-night-open]').addEventListener('click', () => dlg.showModal());
  dlg.querySelectorAll('[data-preset]').forEach((b) => b.addEventListener('click', () => {
    nightPreset = +b.dataset.preset;
    dlg.querySelectorAll('[data-preset]').forEach((x) => x.classList.toggle('on', x === b));
  }));
  $('[data-night-cancel]').addEventListener('click', () => dlg.close());
  $('[data-night-start]').addEventListener('click', () => {
    const catId = $('#night-cat').value;
    const preset = NIGHT.presets[nightPreset];
    dlg.close();
    startGame('barTrivia', catById(catId), { nightPlan: { rounds: preset.rounds }, label: preset.name });
  });

  // Customize dialog (mode + category + presets, one Start).
  const cust = $('#customize-dlg');
  const qp = quickPlayTarget();
  custMode = qp.mode; custCat = qp.cat; custShowAll = !CORE_MODES.includes(custMode);
  renderCustModes(); renderCustPresets(); markCustCat();
  $('[data-customize]').addEventListener('click', () => { renderCustModes(); renderCustPresets(); markCustCat(); cust.showModal(); });
  $('[data-more-modes]').addEventListener('click', () => { custShowAll = !custShowAll; renderCustModes(); });
  $('#cust-cats').querySelectorAll('[data-ccat]').forEach((b) => b.addEventListener('click', () => { custCat = b.dataset.ccat; markCustCat(); }));
  $('[data-cust-start]').addEventListener('click', () => { cust.close(); rememberPlay(custMode, custCat); startGame(custMode, catById(custCat)); });
  $('[data-cust-save]').addEventListener('click', () => {
    const def = `${(catById(custCat) || { name: '' }).name} ${MODES[custMode].title}`;
    const name = prompt('Name this mix', def);
    if (name && name.trim()) { savePreset({ name: name.trim(), mode: custMode, categoryIds: [custCat] }); renderCustPresets(); }
  });
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
      // Grounded generation: prefer REAL corpus questions on the topic; fall back
      // to live generation only when the corpus is thin (no hallucination).
      let qs = Corpus.search(topic, 8);
      if (qs.length < 4) qs = await Wikipedia.generate(topic, 'mixed', 8);
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
function settingsSection() {
  const on = Store.reviewEnabled();
  return `<h2 class="section">Settings</h2>
    <label class="card row review-toggle"><span><b>Review questions</b><div class="muted">Re-ask questions you've missed, spaced out, so they stick. Off = only new questions.</div></span>
      <input type="checkbox" id="review-toggle" ${on ? 'checked' : ''}></label>`;
}
function viewRecords() {
  const recs = Store.records();
  if (!recs.length) return `<h1 class="page-title">Records</h1><div class="empty card pad"><p>No games yet.</p><p class="muted">Play a round and your scores, streaks, and facts to review show up here.</p></div>${settingsSection()}`;
  const lt = Store.lifetime(), st = Store.streak();
  const bests = Object.values(MODES).map((m) => ({ m, best: Store.bestScore(m.id) })).filter((x) => x.best > 0);
  const review = Store.reviewEnabled() ? Store.dueReview(8) : [];
  return `
    <h1 class="page-title">Records</h1>
    <div class="banner card daily"><div><div class="muted">DAILY STREAK</div><div class="big">${st.current} days</div></div><div class="muted">best ${st.best} 🔥</div></div>
    <div class="stat-row">
      ${statBox(lt.games, 'Games', '#8B5CF6')}${statBox(lt.acc + '%', 'Accuracy', '#2D5BFF')}${statBox(lt.correct, 'Correct', '#2FCB8A')}
    </div>
    ${progressSection()}
    ${calibrationSection()}
    <h2 class="section">Personal bests</h2>
    ${bests.map((x) => `<div class="card row"><b>${h(x.m.title)}</b><span class="big-sm">${x.best}</span></div>`).join('') || '<p class="muted">Play a mode to set a best.</p>'}
    ${review.length ? `<h2 class="section">Facts to review</h2><p class="muted">We slip these back into future games.</p>
      ${review.map((q) => `<div class="card pad"><b>${h(q.prompt)}</b><div class="ans">Answer: ${h(q.options[q.correctIndex])}</div></div>`).join('')}` : ''}
    ${settingsSection()}`;
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

// Topic Levels (depth). Plain-language "N more to Level X" so the number means
// something; the confusing breadth pie was removed (Task 8).
function progressSection() {
  const ds = Store.progress();
  const explored = ds.filter((d) => d.total > 0).length;
  const mastered = ds.filter((d) => d.hasWedge).length;
  const rows = ds.filter((d) => d.total > 0).map((d) => {
    const c = catById(d.id), col = catColor(c);
    const remaining = Math.max(0, Math.round((1 - d.levelProgress) * 5 * (d.level + 1)));
    return `<div class="card topic-row">
      <span class="topic-ic" style="background:${col}">${c.symbol}</span>
      <div class="topic-main">
        <div class="topic-head"><b>${h(c.name)}</b>${d.hasWedge ? '<span class="wedge">✓</span>' : ''}<span class="lvl" style="background:${col}">Level ${d.level}</span></div>
        <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, d.levelProgress * 100)}%;background:${col}"></div></div>
        <div class="muted topic-sub">${remaining} more to Level ${d.level + 1}</div>
      </div></div>`;
  }).join('');
  return `<h2 class="section">Your knowledge</h2>
    <p class="muted">Each domain levels up as you answer its questions correctly. You've explored ${explored} of 7 domains and mastered ${mastered}. A ✓ means mastered — 15+ right at 60%+ accuracy.</p>
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
    // Trivia Night: the plan's rounds [[kind, count], …] + the per-round meta for banners.
    this._nightPlan = opts.nightPlan || (mode === 'barTrivia' ? { rounds: NIGHT.presets[1].rounds } : null);
    this._nightRounds = (this._nightPlan?.rounds || []).map(([kind]) => ({ kind, title: NIGHT.roundTitle[kind] || kind }));
    // Stake: the remaining confidence-chip budget + the chip on this question (0 = unset).
    this.stakeTiers = this.mode.id === 'stake' ? STAKE_BUDGET.map((t) => ({ value: t.value, label: t.label, remaining: t.count })) : [];
    this.currentStake = 0;
    this.stakeOutcomes = {}; // F1 calibration: tierValue -> {hits, total}
  }
  async load() {
    let qs;
    if (this._custom) qs = this._custom;
    else if (this.mode.id === 'barTrivia') qs = await this._loadNight();
    else if (this.mode.id === 'daily') qs = Corpus.daily(dayKey(), 7);
    else if (this.mode.id === 'pictureId') {
      await Pictures.load();
      qs = Pictures.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'thisOrThat') {
      await ThisOrThat.load();
      qs = ThisOrThat.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'closestCall') {
      await ClosestCall.load();
      qs = ClosestCall.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'ordering') {
      await Ordering.load();
      qs = Ordering.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'matching') {
      await Matching.load();
      qs = Matching.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'typeAnswer') {
      await TypeAnswer.load();
      qs = TypeAnswer.pull(this.category.id, Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'oddOneOut') {
      await OddOneOut.load();
      qs = OddOneOut.pull('mixed', Store._seen, this.mode.count);
    }
    else if (this.mode.id === 'enumerate') {
      // Small pool (~11), and enumeration is a REPLAYABLE recall drill — naming
      // the countries of Asia again is the point — so ignore the seen-set.
      await Enumerate.load();
      qs = Enumerate.pull('mixed', new Set(), this.mode.count);
    }
    else if (this.mode.id === 'ladder') {
      await Difficulty.load();
      const pool = Corpus.pull('mixed', Store._seen, 80).sort((a, b) => Difficulty.get(a.sourceTitle) - Difficulty.get(b.sourceTitle));
      const need = this.mode.count;
      qs = pool.length >= need ? Array.from({ length: need }, (_, i) => pool[Math.floor(i * (pool.length - 1) / Math.max(1, need - 1))]) : pool;
    }
    else {
      qs = Corpus.pull(this.category.id, Store._seen, this.mode.count);
      if (qs.length < this.mode.count) {
        const topic = this.category.id === 'mixed' ? 'popular' : this.category.name;
        const live = await Wikipedia.generate(topic, this.category.id, this.mode.count - qs.length);
        qs = qs.concat(live);
      }
      // Spaced-repetition review (opt-out in Records → Settings): in a
      // single-category game, only re-ask misses from THAT category — otherwise a
      // missed Film & TV question gets woven into an Arts & Lit round.
      if (Store.reviewEnabled()) {
        let review = Store.dueReview(30);
        if (this.category.id !== 'mixed') review = review.filter((q) => q.categoryID === this.category.id);
        qs = this._weave(qs, review.slice(0, 2));
      }
    }
    this.questions = (this.mode.count === 99 || this.mode.id === 'barTrivia' ? qs : qs.slice(0, this.mode.count));
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
  // Trivia Night: build the round-tagged mixed list from the plan's rounds.
  async _loadNight() {
    const rounds = this._nightPlan?.rounds || NIGHT.presets[1].rounds;
    const all = [];
    const picked = new Set();
    for (let ri = 0; ri < rounds.length; ri++) {
      const [kind, count] = rounds[ri];
      const qs = await this._sourceType(kind, count, new Set([...Store._seen, ...picked]));
      for (const q of qs) { q.roundIndex = ri; all.push(q); picked.add(q.id); }
    }
    return all;
  }
  // Source `count` questions of one TYPE — same loaders the standard game uses.
  async _sourceType(kind, count, seen) {
    switch (kind) {
      case 'pictureId':   await Pictures.load();   return Pictures.pull(this.category.id, seen, count);
      case 'thisOrThat':  await ThisOrThat.load(); return ThisOrThat.pull(this.category.id, seen, count);
      case 'closestCall': await ClosestCall.load(); return ClosestCall.pull(this.category.id, seen, count);
      case 'ordering':    await Ordering.load();   return Ordering.pull(this.category.id, seen, count);
      case 'matching':    await Matching.load();   return Matching.pull(this.category.id, seen, count);
      case 'typeAnswer':  await TypeAnswer.load();  return TypeAnswer.pull(this.category.id, seen, count);
      case 'oddOneOut':   await OddOneOut.load();  return OddOneOut.pull('mixed', seen, count);
      case 'enumerate':   await Enumerate.load();  return Enumerate.pull('mixed', new Set(), count);
      default: {
        let qs = Corpus.pull(this.category.id, seen, count);
        if (qs.length < count) {
          const topic = this.category.id === 'mixed' ? 'popular' : this.category.name;
          qs = qs.concat(await Wikipedia.generate(topic, this.category.id, count - qs.length));
        }
        return qs.slice(0, count);
      }
    }
  }
  // Trivia Night round helpers (for the round banner + end-of-round beat).
  get currentRound() { const ri = this.current?.roundIndex; return ri == null ? null : (this._nightRounds?.[ri] ?? null); }
  get roundCount() { return this._nightRounds?.length ?? 0; }
  get nextRound() {
    const ri = this.current?.roundIndex; if (ri == null) return null;
    const nx = this.questions[this.index + 1]; if (!nx || nx.roundIndex === ri) return null;
    return this._nightRounds?.[nx.roundIndex] ?? null;
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
    const cur = this.current;
    if (cur && cur.closest) { this.currentGuess = Math.round((cur.closest.min + cur.closest.max) / 2); this.lastGuessPoints = 0; }
    if (cur && cur.ordering) {
      let s = cur.ordering.slice();
      for (let i = 0; i < 6 && s.join() === cur.ordering.join(); i++) { for (let k = s.length - 1; k > 0; k--) { const j = Math.floor(Math.random() * (k + 1)); [s[k], s[j]] = [s[j], s[k]]; } }
      this.currentOrder = s; this.lastOrderPoints = 0;
    }
    if (cur && cur.matching) {
      const v = cur.matching.values.slice();
      for (let k = v.length - 1; k > 0; k--) { const j = Math.floor(Math.random() * (k + 1)); [v[k], v[j]] = [v[j], v[k]]; }
      this.matchValues = v; this.matchAssign = cur.matching.keys.map(() => null); this.matchSelectedKey = null; this.lastMatchPoints = 0;
    }
    if (cur && cur.accepted) this.typedText = '';
    if (cur && cur.enumerate) { this.enumFilled = new Set(); this.enumNamed = []; this.enumLastHit = false; this.typedText = ''; }
    this.budget = this._globalRemaining()
      ?? (this.mode.id === 'barTrivia' ? NIGHT.shapeBudget(cur) : this.mode.perQuestion)
      ?? 30;
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
    else { this.remaining = Math.max(0, this.budget - (Date.now() - this.qStart) / 1000); if (this.remaining <= 0) { const c = this.current; return (c?.closest ? this.submitGuess() : c?.ordering ? this.submitOrder() : c?.matching ? this.submitMatch() : c?.accepted ? this.submitText() : c?.enumerate ? this.finishEnum() : this.submit(null)); } }
    updateClock();
  }
  // Type-the-answer (Q6): match typed input against the accepted set.
  submitText() {
    if (this.phase !== 'playing') return;
    const q = this.current, acc = q.accepted; if (!acc) return;
    clearInterval(this.timer);
    const correct = matchesAccepted(this.typedText || '', acc);
    const taken = (Date.now() - this.qStart) / 1000;
    this.answered.push({ q, chosen: correct ? q.correctIndex : -1, correct, taken });
    if (correct) { this.streak++; this.maxStreak = Math.max(this.maxStreak, this.streak); this.score += Scoring.points(true, taken, this.mode.perQuestion ?? 25, this.streak); }
    else this.streak = 0;
    this.phase = 'reveal'; renderGame();
  }
  // Enumeration (Q8): type a guess; fill the first unfilled group it matches.
  // +1 per fill (count-scored, like Sweep). The list you fill IS the score.
  submitEnumGuess(text) {
    if (this.phase !== 'playing') return false;
    const spec = this.current.enumerate; if (!spec) return false;
    this.typedText = '';
    const n = (text || '').trim(); if (!n) { this.enumLastHit = false; renderGame(); return false; }
    for (let i = 0; i < spec.groups.length; i++) {
      if (this.enumFilled.has(i)) continue;
      if (matchesAccepted(n, spec.groups[i])) {
        this.enumFilled.add(i); this.enumNamed.push(spec.groups[i][0]); this.score += 1; this.enumLastHit = true;
        if (this.enumFilled.size === spec.groups.length) { this.finishEnum(); return true; }
        renderGame(); return true;
      }
    }
    this.enumLastHit = false; renderGame(); return false;
  }
  finishEnum() {
    if (this.phase !== 'playing') return;
    const q = this.current, spec = q.enumerate; if (!spec) return;
    clearInterval(this.timer);
    const got = this.enumFilled.size, hit = got > 0 && got * 2 >= spec.groups.length;
    this.answered.push({ q, chosen: hit ? q.correctIndex : -1, correct: hit, taken: this.budget - this.remaining });
    this.phase = 'reveal'; renderGame();
  }
  // Matching (Q5): tap a key to select, tap a value to link; submit scores links.
  selectMatchKey(i) { if (this.phase !== 'playing' || !this.current?.matching) return; this.matchSelectedKey = this.matchSelectedKey === i ? null : i; renderGame(); }
  assignMatchValue(j) {
    if (this.phase !== 'playing' || !this.current?.matching || this.matchSelectedKey == null) return;
    for (let i = 0; i < this.matchAssign.length; i++) if (this.matchAssign[i] === j) this.matchAssign[i] = null;
    this.matchAssign[this.matchSelectedKey] = j; this.matchSelectedKey = null; renderGame();
  }
  matchedValue(i) { const v = this.matchAssign[i]; return v == null ? null : this.matchValues[v]; }
  submitMatch() {
    if (this.phase !== 'playing') return;
    const q = this.current, m = q.matching; if (!m) return;
    clearInterval(this.timer);
    let correct = 0;
    for (let i = 0; i < m.keys.length; i++) if (this.matchedValue(i) === m.values[i]) correct++;
    const pts = m.keys.length ? Math.round(40 * correct / m.keys.length) : 0;
    const perfect = correct === m.keys.length;
    this.lastMatchPoints = pts;
    const taken = (Date.now() - this.qStart) / 1000;
    this.answered.push({ q, chosen: perfect ? q.correctIndex : -1, correct: perfect, taken });
    if (perfect) { this.streak++; this.maxStreak = Math.max(this.maxStreak, this.streak); } else this.streak = 0;
    this.score += pts; this.phase = 'reveal'; renderGame();
  }
  // Ordering (Q4): move an item up/down; lock in (partial credit by inversions).
  moveOrderItem(i, up) {
    if (this.phase !== 'playing' || !this.current?.ordering) return;
    const t = up ? i - 1 : i + 1;
    if (t < 0 || t >= this.currentOrder.length) return;
    [this.currentOrder[i], this.currentOrder[t]] = [this.currentOrder[t], this.currentOrder[i]];
    renderGame();
  }
  submitOrder() {
    if (this.phase !== 'playing') return;
    const q = this.current, correct = q.ordering; if (!correct) return;
    clearInterval(this.timer);
    const rank = {}; correct.forEach((n, i) => (rank[n] = i));
    let inv = 0;
    for (let i = 0; i < this.currentOrder.length; i++) for (let j = i + 1; j < this.currentOrder.length; j++) if (rank[this.currentOrder[i]] > rank[this.currentOrder[j]]) inv++;
    const maxInv = correct.length * (correct.length - 1) / 2;
    const pts = maxInv === 0 ? 0 : Math.round(40 * (1 - inv / maxInv));
    const perfect = inv === 0;
    this.lastOrderPoints = pts;
    const taken = (Date.now() - this.qStart) / 1000;
    this.answered.push({ q, chosen: perfect ? q.correctIndex : -1, correct: perfect, taken });
    if (perfect) { this.streak++; this.maxStreak = Math.max(this.maxStreak, this.streak); } else this.streak = 0;
    this.score += pts;
    this.phase = 'reveal';
    renderGame();
  }
  // Closest Call (M5): move the estimate, and lock it in (proximity, adds-only).
  setGuess(v) {
    if (this.phase !== 'playing' || !this.current?.closest) return;
    const s = this.current.closest;
    this.currentGuess = Math.min(s.max, Math.max(s.min, v));
  }
  submitGuess() {
    if (this.phase !== 'playing') return;
    const q = this.current, s = q.closest; if (!s) return;
    clearInterval(this.timer);
    const error = Math.abs(this.currentGuess - s.answer);
    const pts = error < s.tolerance ? Math.round(50 * (1 - error / s.tolerance)) : 0;
    const close = error <= s.tolerance / 2;
    this.lastGuessPoints = pts;
    const taken = (Date.now() - this.qStart) / 1000;
    this.answered.push({ q, chosen: close ? q.correctIndex : -1, correct: close, taken });
    if (close) { this.streak++; this.maxStreak = Math.max(this.maxStreak, this.streak); } else this.streak = 0;
    this.score += pts;
    this.phase = 'reveal';
    renderGame();
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
        : this.mode.id === 'ladder' ? Scoring.points(true, taken, this.mode.perQuestion ?? this.budget, this.streak) + (Difficulty.get(q.sourceTitle) - 1) * 10
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
    Store.recordTelemetry(this.mode.id, this.answered);
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
  const closest = q.closest ? closestPanel(q.closest) : '';
  const order = q.ordering ? orderingPanel() : '';
  const match = q.matching ? matchingPanel(q.matching) : '';
  const typeP = q.accepted ? typeAnswerPanel() : '';
  const enumP = q.enumerate ? enumeratePanel(q.enumerate) : '';
  const pic = q.image ? `<div class="card pic-card"><img class="pic-img" src="${h(q.image)}" alt="Identify this" loading="eager" onerror="this.parentNode.classList.add('pic-failed')"><span class="pic-fallback muted">Couldn't load the image</span></div>` : '';
  const reveal = game.phase === 'reveal' ? revealCard(q) : '';
  const banner = (game.mode.id === 'barTrivia' && game.currentRound) ? nightBanner() : '';
  const fixedCount = game.mode.id !== 'timeAttack' && game.mode.id !== 'survival';
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
        ${banner}
        ${pic}
        <div class="card qcard"><div class="qcat" style="color:${catColor(cat)}">${h(cat.name.toUpperCase())}</div><div class="qprompt">${h(q.prompt)}</div></div>
        ${sweepGr}
        ${stakeSel}
        ${closest}
        ${order}
        ${match}
        ${typeP}
        ${enumP}
        <div class="opts">${opts}</div>
        ${reveal}
      </div>
      ${game.phase === 'reveal' ? `<button class="btn btn-ink btn-full" data-next>${isLast() ? 'See Results' : 'Next'}</button>` : ''}
    </div>`;
  $('[data-quit]').addEventListener('click', quitGame);
  if (game.phase === 'playing' && !lockAnswers) app.querySelectorAll('[data-opt]').forEach((b) => b.addEventListener('click', () => game.submit(+b.dataset.opt)));
  app.querySelectorAll('[data-stake]').forEach((b) => b.addEventListener('click', () => game.setStake(+b.dataset.stake)));
  const slider = $('#closest-slider');
  if (slider) slider.addEventListener('input', () => { game.setGuess(+slider.value); const v = $('#closest-val'); if (v) v.textContent = closestFmtVal(+slider.value, game.current.closest); });
  const lock = $('[data-lock]'); if (lock) lock.addEventListener('click', () => game.submitGuess());
  app.querySelectorAll('[data-move]').forEach((b) => b.addEventListener('click', () => game.moveOrderItem(+b.dataset.i, b.dataset.move === 'up')));
  const sub = $('[data-submit-order]'); if (sub) sub.addEventListener('click', () => game.submitOrder());
  app.querySelectorAll('[data-mkey]').forEach((b) => b.addEventListener('click', () => game.selectMatchKey(+b.dataset.mkey)));
  app.querySelectorAll('[data-mval]').forEach((b) => b.addEventListener('click', () => game.assignMatchValue(+b.dataset.mval)));
  const ms = $('[data-submit-match]'); if (ms) ms.addEventListener('click', () => game.submitMatch());
  const ti = $('#type-input');
  if (ti) { ti.addEventListener('input', () => { game.typedText = ti.value; }); ti.addEventListener('keydown', (e) => { if (e.key === 'Enter') game.submitText(); }); if (game.phase === 'playing') ti.focus(); }
  const ts = $('[data-submit-type]'); if (ts) ts.addEventListener('click', () => game.submitText());
  const ei = $('#enum-input');
  if (ei) { ei.addEventListener('keydown', (e) => { if (e.key === 'Enter') { game.submitEnumGuess(ei.value); ei.value = ''; ei.focus(); } }); if (game.phase === 'playing') ei.focus(); }
  const es = $('[data-submit-enum]'); if (es) es.addEventListener('click', () => { const el = $('#enum-input'); game.submitEnumGuess(el ? el.value : ''); if (el) { el.value = ''; el.focus(); } });
  const ed = $('[data-done-enum]'); if (ed) ed.addEventListener('click', () => game.finishEnum());
  if (game.phase === 'reveal') $('[data-next]').addEventListener('click', () => game.advance());
  updateClock();
}
function isLast() { return game.mode.id !== 'timeAttack' && game.mode.id !== 'survival' && game.index + 1 >= game.questions.length; }

// Trivia Night round banner — "ROUND 2 OF 5 · PICTURE ROUND" with round dots.
function nightBanner() {
  const r = game.currentRound, n = game.roundCount, cur = (game.current.roundIndex ?? 0);
  const dots = Array.from({ length: n }, (_, i) => `<span class="ndot${i === cur ? ' on' : ''}"></span>`).join('');
  return `<div class="card night-banner"><div class="nb-main"><div class="nb-sub">ROUND ${cur + 1} OF ${n}</div><div class="nb-title">${h(r.title.toUpperCase())}</div></div><div class="ndots">${dots}</div></div>`;
}
// Enumeration (Q8): a count, a text input + Submit + Done, and the named chips.
function enumeratePanel(spec) {
  const live = game.phase === 'playing';
  const chips = (game.enumNamed || []).map((n) => `<span class="enum-chip">${h(n)}</span>`).join('');
  return `<div class="enum-wrap">
    <div class="enum-head"><span class="enum-count">${game.enumFilled.size} / ${spec.groups.length}</span>${live ? '<button class="enum-done" data-done-enum>Done</button>' : ''}</div>
    ${live ? `<div class="type-wrap"><input id="enum-input" class="type-input${game.enumLastHit ? ' enum-hit' : ''}" type="text" placeholder="Name one…" autocomplete="off" autocapitalize="words"><button class="btn type-submit" data-submit-enum>Add</button></div>` : ''}
    ${chips ? `<div class="enum-grid">${chips}</div>` : ''}
  </div>`;
}
// Type-the-answer (Q6): a text input + Submit.
function typeAnswerPanel() {
  const live = game.phase === 'playing';
  return `<div class="type-wrap">
    <input id="type-input" class="type-input" type="text" placeholder="Type your answer…" autocomplete="off" autocapitalize="words" value="${h(game.typedText || '')}" ${live ? '' : 'disabled'}>
    ${live ? '<button class="btn btn-full type-submit" data-submit-type>Submit</button>' : ''}
  </div>`;
}
// Matching (Q5): key rows (tap to select) + value chips (tap to link) + Submit.
function matchingPanel(m) {
  const live = game.phase === 'playing';
  const keys = m.keys.map((k, i) => {
    const mv = game.matchedValue(i);
    const sel = game.matchSelectedKey === i ? ' sel' : '';
    return `<button class="match-key${sel}" data-mkey="${i}" ${live ? '' : 'disabled'}><span>${h(k)}</span><span class="match-val">${mv ? h(mv) : 'tap a value →'}</span></button>`;
  }).join('');
  const vals = game.matchValues.map((v, j) => {
    const used = game.matchAssign.includes(j);
    return `<button class="match-chip" data-mval="${j}" ${(!live || used) ? 'disabled' : ''}>${h(v)}</button>`;
  }).join('');
  return `<div class="match-wrap"><div class="match-keys">${keys}</div><div class="match-vals">${vals}</div>${live ? '<button class="btn btn-full match-submit" data-submit-match>Submit</button>' : ''}</div>`;
}
// Ordering (Q4): rows with up/down + Submit; partial credit by inversions.
function orderingPanel() {
  const live = game.phase === 'playing';
  const rows = game.currentOrder.map((item, i) => `<div class="order-row card">
    <span class="order-n">${i + 1}</span><span class="order-name">${h(item)}</span>
    ${live ? `<button class="order-btn" data-move="up" data-i="${i}" ${i === 0 ? 'disabled' : ''}>▲</button><button class="order-btn" data-move="down" data-i="${i}" ${i === game.currentOrder.length - 1 ? 'disabled' : ''}>▼</button>` : ''}
  </div>`).join('');
  return `<div class="order-wrap">${rows}${live ? '<button class="btn btn-full order-submit" data-submit-order>Submit Order</button>' : ''}</div>`;
}
function closestFmtVal(v, s) { const n = Math.round(v); if (!s.unit) return String(n); const str = Math.abs(n) >= 1000 ? n.toLocaleString() : String(n); return `${str} ${s.unit}`; }
// Closest Call (M5): a range slider + Lock In; proximity-scored.
function closestPanel(s) {
  const live = game.phase === 'playing';
  return `<div class="card closest-card">
    <div class="closest-val" id="closest-val">${closestFmtVal(game.currentGuess, s)}</div>
    <input type="range" id="closest-slider" min="${s.min}" max="${s.max}" step="${s.step}" value="${game.currentGuess}" ${live ? '' : 'disabled'}>
    <div class="closest-ends muted"><span>${closestFmtVal(s.min, s)}</span><span>${closestFmtVal(s.max, s)}</span></div>
    ${live ? '<button class="btn btn-full closest-lock" data-lock>Lock In</button>' : ''}
  </div>`;
}
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
  const closeTag = q.closest ? `<span class="stake-earned${game.lastGuessPoints > 0 ? ' hit' : ''}">+${game.lastGuessPoints}</span>` : '';
  const orderTag = q.ordering ? `<span class="stake-earned${game.lastOrderPoints > 0 ? ' hit' : ''}">+${game.lastOrderPoints}</span>` : '';
  const matchTag = q.matching ? `<span class="stake-earned${game.lastMatchPoints > 0 ? ' hit' : ''}">+${game.lastMatchPoints}</span>` : '';
  const closeLine = q.closest ? `<p class="muted">You said ${closestFmtVal(game.currentGuess, q.closest)} · actual ${closestFmtVal(q.closest.answer, q.closest)} · off by ${Math.abs(Math.round(game.currentGuess - q.closest.answer))}</p>` : '';
  const typeLine = q.accepted ? `<p class="ans">Answer: ${h(q.options[q.correctIndex])}</p>` : '';
  let enumBlock = '';
  if (q.enumerate) {
    const named = new Set(game.enumNamed);
    const tiles = q.enumerate.groups.map((g) => `<span class="enum-tile${named.has(g[0]) ? ' got' : ''}">${h(g[0])}</span>`).join('');
    enumBlock = `<p class="ans">You named ${game.enumFilled.size} of ${q.enumerate.groups.length}</p><div class="enum-grid reveal-grid">${tiles}</div>`;
  }
  const next = (game.mode.id === 'barTrivia' && game.nextRound) ? `<p class="night-next">🏁 Round ${(q.roundIndex ?? 0) + 1} complete · up next: ${h(game.nextRound.title)}</p>` : '';
  return `<div class="card reveal"><div class="reveal-h">${correct ? '✅ Nice — you knew it.' : '💡 Now you know.'}${stakeTag}${closeTag}${orderTag}${matchTag}</div>
    ${closeLine}${typeLine}${enumBlock}${q.explanation ? `<p>${h(q.explanation)}</p>` : ''}${next}${q.sourceURL ? `<a href="${h(q.sourceURL)}" target="_blank" rel="noopener" class="link">Read ${h(q.sourceTitle)} on Wikipedia ↗</a>` : ''}</div>`;
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
  const text = `${header}\n${grid}\n${s.correct}/${s.total} right · ${s.score} pts · ${s.acc}%\nTrivia from all of Wikipedia. Play at ${SITE_URL}`;
  try { if (navigator.share) { await navigator.share({ text }); return; } } catch {}
  try { await navigator.clipboard.writeText(text); toast('Copied to clipboard!'); } catch { toast('Copy failed'); }
}
function toast(msg) {
  const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg; document.body.appendChild(t);
  setTimeout(() => t.remove(), 1800);
}

boot();
