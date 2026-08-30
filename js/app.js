// Tidbits — web app shell: router, views, and the game loop. Mirrors the
// Apple AppStore + GameEngine + views. Vanilla JS, no framework, no build.

import { Corpus, Pictures, ThisOrThat, ClosestCall, Ordering, Matching, TypeAnswer, OddOneOut, Enumerate, Difficulty, matchesAccepted, Wikipedia, DailyBoard } from './api.js';
import { allQuizzes, deleteQuiz, saveCreated, resolveForPlay, migrateLegacySavedSets, getQuiz,
         publishQuiz, fetchSharedQuiz, keepSharedQuiz, quizShareURL } from './quizstore.js';
import { PLAYABLE_MODES, MODE_LABELS, playableMode } from './quiz.js';
import { Store, CATEGORIES, catColor, catById, MODES, NIGHT, STAKE_BUDGET, dayKey, APP_STORES, SITE_URL, CLUB, WeakSpotArena, StoryArchive, answerTextOf, Marathon, marathonAccuracy, KnowledgeAtlas, Expeditions, LinkWall, LinkWallLog } from './store.js';
import { Scoring } from './engine.js';
import { BOTS, houseBot, botById, VsMatch } from './bots.js';
import { FirebaseNet } from './firebase.js';
import { openLive, closeLive } from './live.js';
import { Identity, avatarHue, initialsOf } from './identity.js';
import { Entitlement } from './entitlement.js';
import { Push } from './push.js';
import { Duels } from './duels.js';

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

// L2: sync the daily log across devices when signed in — done-today + the archive follow
// the identity. pushLocal on sign-in so anon plays aren't lost; then pull the union.
async function syncDailyLog(pushLocal = false) {
  if (!Identity.signedIn) return;
  const remote = await Identity.fetchDailyLog();   // read first — the account is authoritative
  // Push only days the account doesn't already have — an established daily score is never
  // overwritten, so replaying a day while logged out can't beat it.
  if (pushLocal) { for (const [day, score] of Object.entries(Store.allDaily())) { if (remote[day] == null) Identity.syncDailyScore(day, score); } }
  // Adopt the account's value for every day (reconciles a cross-device conflict).
  let changed = false;
  for (const [day, score] of Object.entries(remote)) { if (Store.dailyScore(day) !== score) { Store.adoptDaily(day, score); changed = true; } }
  if (changed) render();
}

async function boot() {
  renderLoading('Loading Tidbits…');
  Identity.bootstrap().then(() => { syncDailyLog(); Entitlement.refresh(); });   // + Club status
  Identity.onChange(() => { Entitlement.refresh(); const t = location.hash; if (t.startsWith('#/profile') || t.startsWith('#/records')) render(); });
  try { await Corpus.load(); } catch (e) { /* live fallback still works */ }
  // Migrate off the pre-contract saved-sets format (QUIZ-CONTRACT §7) AFTER the
  // corpus is loaded: run earlier, every id lookup misses and every question gets
  // inlined, which is how a 400-byte quiz becomes a 40KB one.
  migrateLegacySavedSets().then((n) => { if (n) render(); });
  if (!location.hash) location.hash = '#/play';
  // ?expedition=<id> — jump straight to a campaign's map (open convenience,
  // mirrors Apple's TIDBITS_EXPEDITION_MAP verification hook).
  const expeditionParam = new URLSearchParams(location.search).get('expedition');
  if (expeditionParam && Expeditions.named(expeditionParam)) location.hash = `#/expeditions/${expeditionParam}`;
  // ?linkwall=1 — open convenience (mirrors ?expedition=<id>), Feature 6.
  if (new URLSearchParams(location.search).get('linkwall') === '1') location.hash = '#/linkwall';
  // Prefix order matters: '#/daily' also prefixes '#/dailyboard', so an
  // unqualified startsWith here swallowed every board link and started the
  // Daily game instead — the board route below was unreachable.
  if (location.hash === '#/daily' || location.hash.startsWith('#/daily/')) {
    render();
    if (Store.dailyScore(dayKey()) == null) startGame('daily', catById('mixed'));
    return;
  }
  // Shareable Trivia Night deep links: #/night (Pub) or #/night/quick|works.
  if (location.hash.startsWith('#/night')) {
    render();
    const key = location.hash.split('/')[2] || 'pub';
    const idx = { quick: 0, pub: 1, works: 2 }[key] ?? 1;
    startGame('barTrivia', catById('mixed'), { nightPlan: { rounds: NIGHT.presets[idx].rounds }, label: NIGHT.presets[idx].name });
    return;
  }
  render();
  maybeShowOnboarding();
}

// ---------------- Top-level render ----------------
function render() {
  // A shared quiz: #/quiz/<id>. The web is the canonical link target on EVERY
  // platform (QUIZ-CONTRACT §5), so this has to work for someone who has never
  // opened the app before -- no account, no install.
  if (location.hash.startsWith('#/quiz/')) { openSharedQuiz(location.hash.split('/')[2] || ''); return; }
  // A shared single question: #/item/<id>. DEEP_LINKS.md reserves /item/{id} as the
  // canonical twin every platform's per-question share points at, and the web is the
  // LANDING half of that twin — it has to open for someone with no app and no account.
  if (location.hash.startsWith('#/item/')) { openSharedItem(decodeURIComponent(location.hash.slice('#/item/'.length))); return; }
  // Tidbits Live player: #/live or #/live/CODE — a self-managing overlay.
  if (location.hash.startsWith('#/live')) { openLive(location.hash.split('/')[2] || ''); return; }
  closeLive(); // idempotent teardown when the hash leaves #/live
  if (game) {
    if (!game._resultsShown) return; // a LIVE game owns the screen
    game = null;                     // results yield to URL navigation (F-013)
  }
  if (location.hash.startsWith('#/profile')) {
    app.innerHTML = `<main class="main">${viewProfile()}</main>`;
    bindProfile(); document.title = 'Tidbits Trivia'; return;
  }
  if (location.hash.startsWith('#/leaderboard')) {   // Wave E: cross-venue / season standings
    app.innerHTML = `${header(currentTab())}<main class="main">${viewLeaderboard()}</main>`;
    loadLeaderboard(); document.title = 'Tidbits Trivia — Leaderboard'; return;
  }
  if (location.hash.startsWith('#/duels')) {   // L5: async friend duels
    app.innerHTML = `${header(currentTab())}<main class="main">${viewDuels()}</main>`;
    loadDuels(); document.title = 'Tidbits Trivia — Duels'; return;
  }
  if (location.hash.startsWith('#/dailyboard')) {   // the Daily's global board (a layer on the Daily)
    document.title = 'Tidbits Trivia — Daily';
    game = null; renderDailyBoard();
    return;
  }
  if (location.hash.startsWith('#/club')) {   // Tidbits Club — the promo/join surface (rule 6)
    app.innerHTML = `${header(currentTab())}<main class="main">${viewClub()}</main>`;
    bindClub(); document.title = 'Tidbits Club'; return;
  }
  // Tidbits Club EXCLUSIVE — Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2"):
  // a Records "see all" destination, shareable at its own canonical URL
  // (#/archive?domain=…&fav=1, the web's URL-state superpower).
  if (location.hash.startsWith('#/archive')) {
    app.innerHTML = `${header(currentTab())}<main class="main">${viewArchive()}</main>`;
    bindArchive(); document.title = 'Tidbits Trivia — Story Archive'; return;
  }
  // Tidbits Club EXCLUSIVE — Marathon (docs/CLUB-FEATURES-BUILD.md "Feature 3"):
  // the hub (resume/start-over + permanent history), a Home-card + Records
  // destination, shareable at its own canonical URL.
  if (location.hash.startsWith('#/marathon')) {
    app.innerHTML = `${header(currentTab())}<main class="main">${viewMarathon()}</main>`;
    bindMarathon(); document.title = 'Tidbits Trivia — Marathon'; return;
  }
  // Tidbits Club EXCLUSIVE — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md
  // "Feature 4"): a Records "see all" destination, canonical at #/atlas. The
  // anti-Sporcle rule: every domain row here is a tap target into a round —
  // it interprets AND acts, never a passive stats wall.
  if (location.hash.startsWith('#/atlas')) {
    app.innerHTML = `${header(currentTab())}<main class="main">${viewAtlas()}</main>`;
    bindAtlas(); document.title = 'Tidbits Trivia — Knowledge Atlas'; return;
  }
  // Tidbits Club EXCLUSIVE — Link Wall (docs/CLUB-FEATURES-BUILD.md "Feature 6"): a
  // NYT-Connections-style SECOND daily. Canonical at #/linkwall. Building today's
  // puzzle needs match.json loaded (async, like Matching mode), so this route
  // renders a loading state first, mirroring #/dailyboard's async render.
  if (location.hash.startsWith('#/linkwall')) {
    document.title = 'Tidbits Trivia — Link Wall';
    game = null;
    app.innerHTML = `${header(currentTab())}<main class="main">${linkWallLoadingHTML()}</main>`;
    loadLinkWallRoute();
    return;
  }
  // Tidbits Club EXCLUSIVE — Expedition (docs/CLUB-FEATURES-BUILD.md "Feature
  // 5"): the hub (#/expeditions) + a per-campaign map (#/expeditions/<id>) are
  // a REAL preview reachable by EVERYONE (the campaigns are curated content,
  // not player data) — only tapping Play on a stage is Club-gated, never a
  // blank wall.
  if (location.hash.startsWith('#/expeditions')) {
    const id = location.hash.split('/')[2] || null;
    app.innerHTML = `${header(currentTab())}<main class="main">${id ? viewExpeditionMap(id) : viewExpeditions()}</main>`;
    if (id) bindExpeditionMap(id); else bindExpeditions();
    document.title = id ? 'Tidbits Trivia — Expedition' : 'Tidbits Trivia — Expeditions'; return;
  }
  const tab = currentTab();
  app.innerHTML = `
    ${header(tab)}
    <main class="main">${tab === 'play' ? viewHome() : tab === 'create' ? viewCreate() : viewRecords()}</main>`;
  if (tab === 'play') bindHome();
  if (tab === 'create') bindCreate();
  if (tab === 'records') bindRecords();
  document.title = 'Tidbits Trivia';
}

// R-ICON-1 (Decision 036): UI icons are inline SVG, never emoji. Emoji stay in
// CONTENT (share grids, celebration copy, streak data strings).
const ICON = {
  play: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M4 2l9 6-9 6z" fill="currentColor"/></svg>',
  create: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M7 2h2v5h5v2H9v5H7V9H2V7h5z" fill="currentColor"/></svg>',
  records: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M2 13h2.4V6H2zM6.8 13h2.4V3H6.8zM11.6 13H14V8h-2.4z" fill="currentColor"/></svg>',
  die: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><rect x="1.6" y="1.6" width="12.8" height="12.8" rx="3" fill="none" stroke="currentColor" stroke-width="1.7"/><circle cx="5.4" cy="5.4" r="1.15" fill="currentColor"/><circle cx="10.6" cy="5.4" r="1.15" fill="currentColor"/><circle cx="8" cy="8" r="1.15" fill="currentColor"/><circle cx="5.4" cy="10.6" r="1.15" fill="currentColor"/><circle cx="10.6" cy="10.6" r="1.15" fill="currentColor"/></svg>',
  sliders: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><g stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M2 4.2h7M12.4 4.2H14M2 8h2.6M8 8h6M2 11.8h5M10.4 11.8H14"/></g><circle cx="10.6" cy="4.2" r="1.7" fill="currentColor"/><circle cx="5.9" cy="8" r="1.7" fill="currentColor"/><circle cx="8.4" cy="11.8" r="1.7" fill="currentColor"/></svg>',
  globe: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="6.2"/><ellipse cx="8" cy="8" rx="2.8" ry="6.2"/><path d="M2 8h12M2.8 5h10.4M2.8 11h10.4"/></g></svg>',
  flame: '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true"><path d="M8.3 1.2c.3 2.6-3.6 4-3.6 7.4a3.9 3.9 0 007.8 0c0-1.3-.5-2.3-1.2-3.2-.3 1-.9 1.5-1.5 1.5.4-1.6-.2-4-1.5-5.7z" fill="currentColor"/></svg>',
  sun: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><circle cx="8" cy="8" r="3.2" fill="currentColor"/><g stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.4 1.4M11.6 11.6L13 13M13 3l-1.4 1.4M4.4 11.6L3 13"/></g></svg>',
  check: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M2.5 8.5l3.5 3.5 7.5-8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  target: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="6.2"/><circle cx="8" cy="8" r="3.2"/></g><circle cx="8" cy="8" r="1.1" fill="currentColor"/></svg>',
  book: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M2 2.9c0-.6.5-1 1.1-.9 1.7.3 3.3.9 4.9 1.8 1.6-.9 3.2-1.5 4.9-1.8.6-.1 1.1.3 1.1.9v8.7c0 .5-.4.9-.9 1-1.8.3-3.5.9-5.1 1.8h-.8c-1.6-.9-3.3-1.5-5.1-1.8-.5-.1-.9-.5-.9-1z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M8 3.8v9" stroke="currentColor" stroke-width="1.4"/></svg>',
  flag: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M3.2 1.4v13.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M3.2 2.1c1.8-1 3.6.9 5.4 0s3.6.9 3.6.9v5.6c-1.8.9-3.6-.9-5.4 0s-3.6-.9-3.6-.9z" fill="currentColor"/></svg>',
  map: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M1.5 3.1l4-1.5 5 1.5 4-1.5v11l-4 1.5-5-1.5-4 1.5z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M5.5 1.6v10.9M10.5 3.1v10.9" stroke="currentColor" stroke-width="1.3"/></svg>',
  compass: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M10.4 5.6L8.9 8.9 5.6 10.4 7.1 7.1z" fill="currentColor"/></svg>',
  grid: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1.5" y="1.5" width="5.5" height="5.5" rx="1"/><rect x="9" y="1.5" width="5.5" height="5.5" rx="1"/><rect x="1.5" y="9" width="5.5" height="5.5" rx="1"/><rect x="9" y="9" width="5.5" height="5.5" rx="1"/></g></svg>',
  xmark: '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M3 3l10 10M13 3L3 13" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
};

// The portable Tidbits identity — the web twin of the iOS/Android profile screens.
function viewProfile() {
  const p = Identity.profile;
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  if (!p) return `${back}<div class="card pad muted">Setting up your profile…</div>`;
  const hue = avatarHue(p.avatarSeed), r = p.rating;
  const acc = p.stats.questionsAnswered ? Math.round(p.stats.correct / p.stats.questionsAnswered * 100) : 0;
  const line = (label, sub, val) => `<div class="card pad" style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
    <div><div class="muted" style="font-weight:800;font-size:.8rem">${label}</div><div class="muted" style="font-size:.8rem">${sub}</div></div>
    <div style="font-size:2.3rem;font-weight:900;font-variant-numeric:tabular-nums">${val}</div></div>`;
  return `${back}
    <div style="display:flex;flex-direction:column;align-items:center;gap:8px;margin:6px 0 18px">
      <button data-shuffle title="Shuffle your color" style="width:88px;height:88px;border-radius:999px;background:hsl(${hue} 55% 72%);border:3px solid #231E1A;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:2rem;color:#231E1A;cursor:pointer;padding:0">${h(initialsOf(p.name))}</button>
      <button data-rename style="background:none;border:none;cursor:pointer;font-size:1.6rem;font-weight:900;color:#231E1A">${h(p.name)} <span style="font-size:1rem">✎</span></button>
      <div class="muted" style="font-size:.75rem">Tap your avatar to shuffle its color</div>
    </div>
    ${line('TIDBITS RATING', r.provisional ? `Provisional · ${r.games}/15 games` : `${r.games} games rated`, Math.round(r.value))}
    ${line('STREAK', `Longest ${p.streak.longest} · ${p.streak.freezes} freeze${p.streak.freezes === 1 ? '' : 's'}`, p.streak.current)}
    <div class="stat-row">${statBox(p.stats.gamesPlayed, 'Games', '#8B5CF6')}${statBox(acc + '%', 'Accuracy', '#2D5BFF')}${statBox(p.stats.liveNights, 'Live nights', '#FF5C35')}${statBox(p.stats.venuesVisited, 'Venues', '#2FCB8A')}</div>
    ${authBlock()}`;
}

// Federated sign-in makes records durable + roam across devices (docs/PLAYER-IDENTITY-CONTRACT.md).
function authBlock() {
  if (Identity.signedIn) {
    return `<div class="card pad" style="margin-top:16px;text-align:center"><div class="muted">✓ Signed in${Identity.email ? ' as ' + h(Identity.email) : ''}</div><div class="muted" style="font-size:.8rem">Your records are saved and follow you to every device.</div><button data-signout style="margin-top:12px;padding:8px 18px;font-weight:700;border:2px solid #231E1A;border-radius:12px;background:#fff;cursor:pointer">Sign out</button></div>${deleteAccountBlock()}`;
  }
  const btn = (id, label) => `<button data-signin="${id}" style="flex:1;padding:14px;font-weight:800;border:2.5px solid #231E1A;border-radius:14px;background:#fff;box-shadow:3px 3px 0 #231E1A;cursor:pointer">${label}</button>`;
  return `<div style="margin-top:18px">
    <div class="muted" style="text-align:center;margin-bottom:10px;font-weight:700">Save your progress — sign in so your records follow you to any device.</div>
    <div style="display:flex;gap:10px" id="signin-row">${btn('google.com', 'Continue with Google')}${btn('apple.com', 'Continue with Apple')}</div></div>${deleteAccountBlock()}`;
}

// Account deletion (App Store 5.1.1(v) / Play's equivalent), shown whether or not the
// player signed in — Tidbits provisions a real anonymous account for everyone, and that
// account is what holds their rating, streak and board rows. Quiet, but never hidden:
// the requirement is that it is findable, not that it is prominent.
function deleteAccountBlock() {
  return `<div style="margin-top:22px;text-align:center">
    <button data-delete-account style="padding:8px 18px;font-weight:700;border:2px solid #C0392B;border-radius:12px;background:#fff;color:#C0392B;cursor:pointer">Delete account</button>
    <div class="muted" style="font-size:.78rem;margin-top:6px">Permanently removes your profile, rating, streak and board entries.</div></div>`;
}
function bindProfile() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/records'; });
  app.querySelector('[data-rename]')?.addEventListener('click', () => {
    const name = prompt('Display name — what other players and venues see:', Identity.profile?.name || '');
    if (name != null) { Identity.rename(name); render(); }
  });
  app.querySelector('[data-shuffle]')?.addEventListener('click', () => { Identity.rerollAvatar(); render(); });   // L4 cosmetics
  app.querySelector('[data-signout]')?.addEventListener('click', async () => {
    if (!confirm('Sign out? Your records stay saved to your account — sign in again to bring them back.')) return;
    try { await Identity.signOut(); Entitlement.clearOnSignOut(); render(); }
    catch (e) { console.error('[identity] sign-out error', e); alert('Sign-out didn’t complete. Please try again.'); }
  });
  app.querySelector('[data-delete-account]')?.addEventListener('click', async (ev) => {
    if (!confirm('Delete your account?\n\nYour profile, rating, streak, saved records and leaderboard entries are permanently removed. This cannot be undone.')) return;
    const btn = ev.currentTarget;
    btn.disabled = true; btn.textContent = 'Deleting…';
    const ok = await Identity.deleteAccount();
    Entitlement.clearOnSignOut();
    render();
    // A failed delete must SAY so — a silent no-op is the thing App Review rejects.
    if (!ok) alert(Identity.deleteError || 'Couldn’t delete your account. Please try again.');
    else alert('Your account has been deleted. You’re playing as a new anonymous player.');
  });
  app.querySelectorAll('[data-signin]').forEach((b) => b.addEventListener('click', async () => {
    const row = document.getElementById('signin-row');
    if (row) row.style.opacity = '0.5';
    b.disabled = true;
    try {
      const merged = await Identity.signIn(b.dataset.signin);
      syncDailyLog(true);   // push anon daily plays, pull the cross-device union
      render();
      if (merged) setTimeout(() => alert('Welcome back — we combined your two profiles, so nothing was lost.'), 50);
    } catch (e) {
      if (row) row.style.opacity = '1';
      b.disabled = false;
      console.error('[identity] sign-in error', e);
      if (e?.code !== 'auth/popup-closed-by-user' && e?.code !== 'auth/cancelled-popup-request') {
        alert('Sign-in didn’t complete (' + (e?.code || e?.message || 'unknown error') + '). Please try again.');
      }
    }
  }));
}

function header(tab) {
  const tabBtn = (id, label, icon) => `<a class="tab ${tab === id ? 'active' : ''}" href="#/${id}">${icon}<span>${label}</span></a>`;
  return `<header class="topbar">
    <div class="brand">TIDBITS</div>
    <nav class="tabs">
      ${tabBtn('play', 'Play', ICON.play)}
      ${tabBtn('create', 'Create', ICON.create)}
      ${tabBtn('records', 'Records', ICON.records)}
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
  // .weakSpot / .marathon are Club-gated and never a remembered/random default
  // (mirrors the Apple AppStore fix — a Club mode can't leak into the free
  // Quick Play habit).
  if (m && MODES[m] && m !== 'weakSpot' && m !== 'marathon' && c) return { mode: m, cat: c };
  return { mode: 'classic', cat: 'mixed' };
}
function rememberPlay(mode, catId) {
  if (mode === 'daily' || mode === 'weakSpot' || mode === 'marathon') return;
  localStorage.setItem('tidbits.lastMode', mode);
  localStorage.setItem('tidbits.lastCat', catId);
}
function hasQuickPlayHistory() { return !!localStorage.getItem('tidbits.lastMode'); }
// Custom Mix memory — so Quick Play can replay the last multi-select.
function rememberMix(modes, catId) {
  rememberPlay('mix', catId);
  localStorage.setItem('tidbits.mixModes', modes.join(','));
}
function lastMixModes() {
  return (localStorage.getItem('tidbits.mixModes') || '').split(',').filter((m) => MODES[m] && m !== 'mix');
}
function startMixOrSingle(modes, catId) {
  if (modes.length === 1) { rememberPlay(modes[0], catId); startGame(modes[0], catById(catId)); return; }
  rememberMix(modes, catId);
  startGame('mix', catById(catId), { mixModes: modes });
}
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
        <div class="hero-title">${ICON.play} QUICK PLAY</div>
        <div class="hero-sub">${h(qpMode.toUpperCase())} · ${h(qpCat.toUpperCase())}</div>
        <div class="hero-hint">${first ? 'Tap to play — customize anytime' : 'Jump straight into a round'}</div>
      </div>
    </button>
    <div class="quick-actions">
      <button class="btn btn-quiet" data-surprise>${ICON.die}<span>Surprise me</span></button>
      <button class="btn btn-quiet" data-customize>${ICON.sliders}<span>Customize</span></button>
    </div>
    ${dailyBanner()}
    <button class="banner card night-banner-cta" data-night-open><div><div class="banner-title">TRIVIA NIGHT</div>
      <div class="muted">Host or join a night of mixed rounds.</div></div><span class="chev">›</span></button>
    <h2 class="section">More ways to play</h2>
    <div class="home-tiles">
      <button class="tile card mp" data-multiplayer><span class="tile-ico">${ICON.globe}</span><span class="tile-name">Online Multiplayer</span><span class="tile-sub">Play vs CPU now</span></button>
    </div>
    ${clubDoorCard()}
    <dialog id="mp-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Online Multiplayer</h2>
        <p class="muted">Face an opponent on the same questions — fastest correct answers win.</p>
        <button type="button" class="night-preset" data-quickmatch><b>${ICON.globe} Quick Match</b><span class="muted">Find another player online — same questions, best score wins</span></button>
        <h3 class="section">Play a CPU opponent now</h3>
        ${botRows()}
        <div class="night-actions"><button type="button" class="btn" data-mp-close>Close</button></div>
      </div>
    </dialog>
    <dialog id="night-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Trivia Night</h2>
        <p class="muted">A night of mixed rounds — every kind of question. Each answer ends on a fact to learn.</p>
        <button type="button" class="night-preset" data-live-join><b>${ICON.globe} Join a game</b><span class="muted">Enter a host's 4-letter code — join a Tidbits Live event</span></button>
        <div class="night-or muted">or start your own</div>
        <div class="night-presets">
          ${NIGHT.presets.map((p, i) => `<button type="button" class="night-preset${i === 1 ? ' on' : ''}" data-preset="${i}"><b>${h(p.name)}</b>
            ${p.rounds.map(([k, n], ri) => `<span class="muted round-line">${ri + 1}. ${h(NIGHT.roundTitle[k] || k)} · ${n} questions</span>`).join('')}</button>`).join('')}
        </div>
        <label class="night-cat-label">Category
          <select id="night-cat">${CATEGORIES.map((c) => `<option value="${c.id}">${h(c.name)}</option>`).join('')}</select>
        </label>
        <div class="night-actions">
          <button type="button" class="btn" data-night-cancel>Cancel</button>
          <button type="button" class="btn" data-night-start>Play solo</button>
          <button type="button" class="btn btn-primary" data-night-host>Host for others</button>
        </div>
      </div>
    </dialog>
    <dialog id="daily-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Previous Tidbits</h2>
        <p class="muted">Every day has its own set of 7 — the same for everyone. Catching up doesn't change your streak.</p>
        <div class="daily-list">
          ${dailyArchiveRows()}
        </div>
        <div class="night-actions"><button type="button" class="btn" data-daily-close>Close</button></div>
      </div>
    </dialog>
    <dialog id="customize-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Customize a game</h2>
        <h3 class="section">Mode</h3>
        <div class="chips" id="cust-modes"></div>
        <p class="muted" id="cust-blurb"></p>
        <button type="button" class="link-btn" data-more-modes>Show all modes</button>
        <h3 class="section">Category</h3>
        <div class="chips" id="cust-cats">
          ${CATEGORIES.map((c) => `<button type="button" class="chip" data-ccat="${c.id}">${h(c.name)}</button>`).join('')}
        </div>
        <p class="muted" id="cust-cat-note" hidden></p>
        <div id="cust-presets"></div>
        <div class="night-actions">
          <button type="button" class="btn" data-cust-save>Save preset</button>
          <button type="button" class="btn btn-primary" data-cust-start>Start</button>
        </div>
      </div>
    </dialog>
    ${appsPromo()}`;
}

// Play vs CPU (Decision 038): the four opponents. Bots are ALWAYS labeled CPU.
function recentAccuracy() {
  const recs = Store.records().slice(0, 20);
  const total = recs.reduce((n, r) => n + r.total, 0);
  if (!total) return 0.6;
  return recs.reduce((n, r) => n + r.correct, 0) / total;
}
function botRows() {
  const rows = [
    [houseBot(recentAccuracy()), 'Adapts to how you\u2019ve been playing \u2014 a fair fight'],
    [BOTS.rookie, 'Takes it easy. Strong on sports and film'],
    [BOTS.regular, 'A solid all-rounder. Loves history'],
    [BOTS.ace, 'Fast and sharp. Science is its home turf'],
  ];
  return rows.map(([b, blurb]) => `<button type="button" class="night-preset bot-row" data-bot="${b.id}">
      <b>${h(b.name)} <span class="cpu-tag">CPU</span></b><span class="muted">${blurb}</span></button>`).join('');
}

// Daily banner (R-DAILY-1): play-once; locked state opens the archive.
function dailyBanner() {
  const score = Store.dailyScore(dayKey());
  const day = Identity.profile?.streak?.current || 0;
  const flame = day >= 2 ? `🔥 ${day}-day streak` : '';
  if (score == null) {
    const sub = flame ? `${flame} — play today's 7 to keep it going` : '7 questions. Everyone gets the same set. Start your streak.';
    return `<button class="banner card daily" data-daily><div><div class="banner-title">${ICON.sun} DAILY TIDBIT</div>
      <div class="muted">${sub}</div></div><span class="chev">›</span></button>`;
  }
  return `<button class="banner card daily" data-daily><div><div class="banner-title">${ICON.check} DAILY TIDBIT</div>
    <div class="muted">Done for today — you scored ${score}.${flame ? ` ${flame} kept alive.` : ''} New set tomorrow.</div>
    <div class="muted"><u data-daily-board>See how the world did</u> · <u>Play previous days</u></div></div><span class="chev">›</span></button>`;
}



// Members launch the arena directly (built from their own local misses);
// everyone else goes to the existing paywall route (rule 6 — never a blank wall).
function openWeakSpot() {
  if (!Entitlement.isClub) { location.hash = '#/club'; return; }
  const round = WeakSpotArena.build((catId, excluding, limit) => Corpus.pull(catId, excluding, limit));
  if (round.questions.length < 2) { renderWeakSpotEmpty(); return; }
  startGame('weakSpot', catById('mixed'), {
    custom: round.questions, weakSpotReasons: round.reasons, weakSpotMissCount: round.missCount,
  });
}

// Below the floor of true misses (and no domain history to fill from either) —
// the honest empty state, never the generic "no questions" error.
function renderWeakSpotEmpty() {
  app.innerHTML = `<div class="center-screen">
    <h2>Not enough misses yet</h2>
    <p class="muted">Play a few rounds first — your misses become your arena.</p>
    <button class="btn btn-primary" data-back>Back</button>
  </div>`;
  $('[data-back]').addEventListener('click', render);
}


function marathonResumeMessage() {
  const run = Marathon.inProgress();
  return run ? `Question ${run.currentIndex + 1} of ${run.ids.length} — resume where you left off, or start a fresh run.` : '';
}

// Members with a run in progress get the Resume/Start Over dialog; with no run,
// they launch straight into a fresh one. Non-members see the existing paywall —
// never a blank wall.
function openMarathon() {
  if (!Entitlement.isClub) { location.hash = '#/club'; return; }
  if (Marathon.inProgress()) { $('#marathon-dlg').showModal(); return; }
  startMarathonRound(false);
}

// Resume the in-progress run if one exists (unless `startOver`), else start a
// fresh one. Loads only the REMAINING questions — the HUD adds the run's
// currentIndex back in so the player always sees their true position out of 200.
function startMarathonRound(startOver) {
  const allIds = Corpus.questions.map((q) => q.id);
  const run = startOver ? Marathon.startNew(allIds) : (Marathon.inProgress() || Marathon.startNew(allIds));
  const byId = new Map(Corpus.questions.map((q) => [q.id, q]));
  const remaining = Marathon.remainingIds(run).map((id) => byId.get(id)).filter(Boolean);
  if (!remaining.length) {
    // Edge case only (a run somehow already at its full length without having
    // been finished) — close it out rather than show a blank round.
    const score = Marathon.finish(run);
    game = null;
    renderMarathonResults(score);
    return;
  }
  startGame('marathon', catById('mixed'), { custom: remaining, marathonRun: run, marathonOffset: run.currentIndex });
}


// Tidbits Club EXCLUSIVE — Expedition (docs/CLUB-FEATURES-BUILD.md "Feature 5").
// The hub: pick a campaign (progress-aware subtitle), plus a Completed shelf.
// Reachable by everyone — no Club gate here (see the design spec's "map as a
// real preview" rule); only Play (bindExpeditionMap) is gated.
function viewExpeditions() {
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  const certs = Expeditions.certificates();
  return `${back}<h1 class="page-title">Expeditions</h1>
    <p class="muted">Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace.</p>
    ${Expeditions.all.map(expeditionRowHTML).join('')}
    ${certs.length ? expeditionCertificatesShelfHTML(certs) : ''}`;
}

function expeditionRowHTML(expedition) {
  const p = Expeditions.progress(expedition.id);
  const hasCert = Expeditions.certificates().some((c) => c.expeditionId === expedition.id);
  const subtitle = p
    ? `Stage ${Math.min(p.currentStageIndex + 1, expedition.stages.length)} of ${expedition.stages.length} — tap to continue`
    : hasCert ? 'Completed — tap to play again' : expedition.subtitle;
  const col = catColor(catById(expedition.domain));
  return `<a href="#/expeditions/${expedition.id}" class="card pad expedition-row" style="display:flex;align-items:center;gap:12px;background:${col};color:#fff;margin-bottom:12px">
    <span style="font-size:1.7em;line-height:1">${expedition.symbol}</span>
    <span style="flex:1"><b style="text-transform:uppercase;letter-spacing:.02em">${h(expedition.title)}</b>
      <div style="font-size:.85em;opacity:.92">${h(subtitle)}</div></span>
    <span class="chev">›</span></a>`;
}

function expeditionCertificatesShelfHTML(certs) {
  return `<h2 class="section">Completed</h2>
    ${certs.map((c) => `<div class="card pad" style="display:flex;align-items:center;gap:12px;margin-bottom:10px">
      <span style="font-size:1.4em">🏅</span>
      <span style="flex:1"><b>${h(c.title)}</b>
        <div class="muted" style="font-size:.85em">${c.stagesCompleted} stages · ${c.totalScore} correct · ${h(new Date(c.completedAt).toLocaleDateString())}</div></span>
    </div>`).join('')}`;
}

function bindExpeditions() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/play'; });
}

// An expedition's detail = the map/path of stages (locked/current/done
// markers) — a REAL preview even for non-members (MONETIZATION §4a: never a
// blank wall). Only tapping Play on the current stage is Club-gated.
function viewExpeditionMap(id) {
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  const expedition = Expeditions.named(id);
  if (!expedition) return `${back}<div class="empty card pad"><p>Expedition not found.</p></div>`;
  const club = Entitlement.isClub;
  const p = Expeditions.progress(id);
  const hasCert = Expeditions.certificates().some((c) => c.expeditionId === id);
  const currentStageIndex = p ? Math.min(p.currentStageIndex, expedition.stages.length - 1) : 0;
  const col = catColor(catById(expedition.domain));
  const statusLine = (hasCert && !p)
    ? '🏅 Completed — play again for another certificate'
    : `${expedition.stages.length} stages · pick up where you left off, any time`;
  const stageRows = expedition.stages.map((stage) => expeditionStageRowHTML(stage, currentStageIndex, col)).join('');
  const paywallNote = club ? '' : `<div class="card pad" style="text-align:center;margin-top:14px">
    <p class="muted">Join Tidbits Club to play this expedition. Everything above is a preview — no charge to look around.</p>
    <a href="#/club" class="btn btn-primary" style="margin-top:10px;display:inline-block;text-decoration:none">Join Tidbits Club</a></div>`;
  return `${back}<h1 class="page-title">${h(expedition.title)}</h1>
    <p class="muted">${h(expedition.subtitle)}</p>
    <p class="muted" style="font-weight:700">${h(statusLine)}</p>
    ${stageRows}
    ${paywallNote}`;
}

function expeditionStageRowHTML(stage, currentStageIndex, domainColor) {
  const done = stage.index < currentStageIndex;
  const isCurrent = stage.index === currentStageIndex;
  const locked = !done && !isCurrent;
  const markerBg = done ? 'var(--color-mint)' : isCurrent ? domainColor : 'var(--color-surface)';
  const markerContent = done ? '✓' : locked ? '🔒' : String(stage.index + 1);
  const playBtn = isCurrent ? `<button type="button" class="btn btn-primary" data-expedition-play="${stage.index}" style="margin-top:8px">Play</button>` : '';
  return `<div class="card pad expedition-stage-row" style="opacity:${locked ? 0.55 : 1};margin-bottom:10px">
    <span class="expedition-stage-marker" style="background:${markerBg}">${markerContent}</span>
    <span style="flex:1">
      <div class="body-strong">${h(stage.title)}</div>
      <div class="muted" style="font-size:.85em">${h(stage.blurb)}</div>
      ${playBtn}
    </span>
  </div>`;
}

function bindExpeditionMap(id) {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/expeditions'; });
  app.querySelectorAll('[data-expedition-play]').forEach((b) => b.addEventListener('click', () => {
    if (!Entitlement.isClub) { location.hash = '#/club'; return; }
    startExpeditionStage(id, +b.dataset.expeditionPlay);
  }));
}

// Route the stage's category + difficulty band into the EXISTING 'classic'
// launch path — an Expedition is not a new game engine. A stage plays as a
// normal round (it writes a normal GameRecord via Game._persist — see _end())
// and is replayable on a miss (a fresh pull each attempt).
function startExpeditionStage(id, stageIndex) {
  const expedition = Expeditions.named(id);
  const stage = expedition && Expeditions.stage(expedition, stageIndex);
  if (!expedition || !stage) return;
  const questions = Expeditions.startStage(expedition, stageIndex, (catId, excluding, limit) => Corpus.pull(catId, excluding, limit));
  if (!questions.length) {
    app.innerHTML = `<div class="center-screen"><h2>Couldn't load this stage</h2><p class="muted">Please try again.</p><button class="btn btn-primary" data-back>Back</button></div>`;
    $('[data-back]').addEventListener('click', () => { location.hash = `#/expeditions/${id}`; });
    return;
  }
  startGame('classic', catById(stage.categoryId), { custom: questions, label: stage.title, expeditionId: id, expeditionStageIndex: stageIndex });
}

// The post-stage beat: pass unlocks the next stage (or, on the last stage,
// writes the certificate); fail leaves the player on the same stage, "Try
// again." A stage is a normal round — game._persist() already wrote its
// GameRecord — this screen adds the campaign-specific pass/fail interpretation.
function renderExpeditionStageResult() {
  const expedition = Expeditions.named(game._expeditionId);
  const stage = Expeditions.stage(expedition, game._expeditionStageIndex);
  const outcome = game._expeditionOutcome || { passed: false, certificate: null };
  const s = game.summary();
  const passed = outcome.passed;
  const cert = outcome.certificate;
  const nextStageNumber = Math.min(stage.index + 2, expedition.stages.length);
  const headline = cert ? 'EXPEDITION COMPLETE' : passed ? `STAGE ${stage.index + 1} PASSED` : 'NOT QUITE';
  const bodyLine = cert
    ? `You completed ${expedition.title} — every stage, start to finish.`
    : passed
      ? `${stage.title} is done. Stage ${nextStageNumber} just unlocked.`
      : `Needed ${stage.passBar} of ${stage.questionCount} to advance — you got ${s.correct}. Give it another go.`;
  const certCard = cert ? `<div class="card pad" style="text-align:center;background:#FF5DA2;color:#fff;margin-bottom:16px">
      <div class="muted" style="color:rgba(255,255,255,.85)">CERTIFICATE EARNED</div>
      <div style="font-size:1.3em;font-weight:900">${h(cert.title)}</div>
      <div class="muted" style="color:rgba(255,255,255,.85)">${cert.stagesCompleted} stages · ${cert.totalScore} correct total</div>
    </div>` : '';
  app.innerHTML = `
    <div class="results">
      <div class="card scorecard" style="--tint:${passed ? '#2FCB8A' : '#FF5C5C'}">
        <div class="muted">${h(headline)}</div>
        <div class="huge">${s.correct}/${s.total}</div>
        <div class="muted">${h(bodyLine)}</div>
      </div>
      ${certCard}
      <div class="stat-row">${statBox(s.correct + '/' + s.total, 'Correct', '#2D5BFF')}${statBox(stage.passBar, 'Pass bar', '#FF5DA2')}${statBox(`${Math.min(stage.index + (passed ? 2 : 1), expedition.stages.length)}/${expedition.stages.length}`, 'Stage', '#1A1714')}</div>
      ${passed
        ? `<button class="btn btn-primary btn-full" data-expedition-continue>${cert ? 'Done' : 'Continue'}</button>`
        : `<button class="btn btn-primary btn-full" data-expedition-retry>Try Again</button>
           <button class="btn btn-text btn-full" data-expedition-map>Back to map</button>`}
    </div>`;
  $('[data-expedition-continue]')?.addEventListener('click', () => { game = null; location.hash = `#/expeditions/${expedition.id}`; });
  $('[data-expedition-map]')?.addEventListener('click', () => { game = null; location.hash = `#/expeditions/${expedition.id}`; });
  $('[data-expedition-retry]')?.addEventListener('click', () => { game = null; startExpeditionStage(expedition.id, stage.index); });
}




// The trap to avoid (design spec): "five analytics screens reads as a Sporcle
// stats page." So EVERY domain row here is a tap target that launches a real
// round in that domain (the same category-filtered launch Customize/Quick Play
// use) — it interprets AND acts, never a passive readout. Non-members get a
// real preview (their own strongest/weakest domain, or an honest sample) + the
// paywall — never a blank wall.
function viewAtlas() {
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  if (!Entitlement.isClub) {
    const preview = KnowledgeAtlas.previewLine() || "Club maps every domain you play across 12 months and shows what's rising or drifting.";
    return `${back}<h1 class="page-title">Knowledge Atlas</h1>
      <div class="card pad" style="margin-bottom:14px"><p class="body-strong">${h(preview)}</p></div>
      <div class="card pad" style="text-align:center">
        <p class="body-strong">A map of what you actually know, by domain, over time.</p>
        <p class="muted">Plain accuracy and sample counts — no opaque score. Tap any domain to play a round in it.</p>
        <a href="#/club" class="btn btn-primary" style="margin-top:12px;display:inline-block;text-decoration:none">Join Tidbits Club</a>
      </div>`;
  }
  const domains = KnowledgeAtlas.domains();
  const decaying = KnowledgeAtlas.decayRadar();
  if (!domains.length) {
    return `${back}<h1 class="page-title">Knowledge Atlas</h1>
      <div class="empty card pad"><p class="body-strong">Not enough history yet.</p>
      <p class="muted">Play across a few domains and your Atlas fills in — it needs a few weeks of history to show a trajectory.</p></div>`;
  }
  return `${back}<h1 class="page-title">Knowledge Atlas</h1>
    <p class="muted">Your accuracy by domain over the trailing 12 months. Tap any domain to play a round in it.</p>
    ${domains.map(atlasDomainRowHTML).join('')}
    ${decaying.length ? atlasDecaySectionHTML(decaying) : ''}`;
}

// Domain row: accuracy + sample size + a trajectory arrow (▲▼) — every number
// a door, per the design spec, so the whole row is a tap target into a round.
function atlasDomainRowHTML(d) {
  const c = catById(d.id), col = catColor(c);
  const traj = d.trajectoryDelta == null ? '' :
    `<span class="traj ${d.trajectoryDelta >= 0 ? 'up' : 'down'}">${d.trajectoryDelta >= 0 ? '▲' : '▼'}${Math.round(Math.abs(d.trajectoryDelta) * 100)}</span>`;
  return `<button class="card topic-row rec-tap" data-atlas-domain="${d.id}">
    <span class="topic-ic" style="background:${col}">${c.symbol}</span>
    <div class="topic-main">
      <div class="topic-head"><b>${h(c.name)}</b>${traj}<span class="lvl" style="background:${col}">${Math.round(d.accuracy * 100)}%</span></div>
      <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, d.accuracy * 100)}%;background:${col}"></div></div>
      <div class="muted topic-sub">${d.correct}/${d.total} answered · last 12 months</div>
    </div><span class="chev">›</span></button>`;
}

// Decay radar: domains that were strong 6+ months ago and have since slipped —
// each carries its own "Shore it up" round rather than just a number.
function atlasDecaySectionHTML(decaying) {
  return `<h2 class="section">Decay radar</h2>
    <p class="muted">Domains you were strong in 6+ months ago that have since slipped.</p>
    ${decaying.map((d) => {
      const c = catById(d.id);
      return `<div class="card game-row atlas-decay-row">
        <span class="game-main"><span class="game-head"><b>${h(c.name)}</b></span>
        <span class="muted game-sub">${Math.round(d.pastAccuracy * 100)}% then → ${Math.round(d.recentAccuracy * 100)}% now</span></span>
        <button type="button" class="btn btn-primary" data-atlas-decay="${d.id}">Shore it up</button>
      </div>`;
    }).join('')}`;
}

function bindAtlas() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/records'; });
  if (!Entitlement.isClub) return;
  app.querySelectorAll('[data-atlas-domain]').forEach((b) => b.addEventListener('click', () => startGame('classic', catById(b.dataset.atlasDomain))));
  app.querySelectorAll('[data-atlas-decay]').forEach((b) => b.addEventListener('click', () => startGame('classic', catById(b.dataset.atlasDecay), { label: 'Shore it up' })));
}

let archiveDomain = null, archiveFilter = null, archiveText = '';

// Members get the real searchable library. Non-members land on the SAME canonical
// #/archive URL but see a real preview (their own most-recent story, else an
// honest static line) + the paywall panel → #/club — never a blank wall, and
// never a gate on the free in-moment reveal itself (R-MON-1).
function viewArchive() {
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  if (!Entitlement.isClub) {
    // A REAL preview when a story exists locally; else an honest sample — never
    // a nag, and never a blank wall (MONETIZATION §4a).
    const preview = StoryArchive.previewLine() || '“Marie Curie is the only person to win Nobel Prizes in two different sciences.” — Club keeps every story you unlock, searchable forever.';
    return `${back}<h1 class="page-title">Story Archive</h1>
      <div class="card pad" style="margin-bottom:14px"><p class="body-strong">${h(preview)}</p></div>
      <div class="card pad" style="text-align:center">
        <p class="body-strong">Club keeps every story you unlock, searchable forever.</p>
        <p class="muted">A permanent, searchable library of every fact you've met — favorite the ones worth keeping.</p>
        <a href="#/club" class="btn btn-primary" style="margin-top:12px;display:inline-block;text-decoration:none">Join Tidbits Club</a>
      </div>`;
  }
  const qp = new URLSearchParams(location.hash.split('?')[1] || '');
  archiveDomain = qp.get('domain') || null;
  archiveFilter = qp.get('fav') === '1' ? 'fav' : null;
  archiveText = '';
  const domains = StoryArchive.domainsSeen();
  const statusChip = (id, label) => `<button type="button" class="chip${(archiveFilter || 'all') === id ? ' on' : ''}" data-astatus="${id}">${label}</button>`;
  const domainChip = (id, label) => `<button type="button" class="chip${(archiveDomain || 'all') === id ? ' on' : ''}" data-adomain="${id}">${label}</button>`;
  return `${back}<h1 class="page-title">Story Archive</h1>
    <p class="muted">${StoryArchive.count()} stories kept — search or filter, then tap one to read it again.</p>
    <input type="search" id="archive-search" class="input" placeholder="Search prompts, answers, stories…" style="margin-bottom:10px">
    <div class="chips wrap" id="archive-status-chips">
      ${statusChip('all', 'All')}${statusChip('fav', '★ Favorites')}${statusChip('missed', 'Missed')}${statusChip('gotit', 'Got it')}
    </div>
    ${domains.length ? `<div class="chips wrap" id="archive-domain-chips" style="margin-top:8px">
      ${domainChip('all', 'All domains')}${domains.map((d) => domainChip(d, catById(d).name)).join('')}
    </div>` : ''}
    <div id="archive-results">${archiveResultsHTML()}</div>`;
}

function archiveResultsHTML() {
  if (!StoryArchive.count()) return `<div class="empty card pad" style="margin-top:14px"><p>Play a few rounds — the stories you unlock are kept here forever.</p></div>`;
  const results = StoryArchive.search(archiveText, { domain: archiveDomain, filter: archiveFilter });
  if (!results.length) return `<div class="empty card pad" style="margin-top:14px"><p>No stories match.</p></div>`;
  return `<div style="margin-top:14px">${results.map(archiveCardHTML).join('')}</div>`;
}

function archiveCardHTML(s) {
  const q = s.q, cat = catById(q.categoryID || 'mixed');
  return `<button type="button" class="card pad rec-tap story-card" data-story="${h(q.id)}" style="margin-bottom:10px">
    <div class="story-meta">
      <span class="lvl" style="background:${catColor(cat)}">${h(cat.name)}</span>
      <span class="muted">${relTime(s.last)}</span>
      <span class="ans-seal ${s.everCorrect ? 'ok' : 'no'}" style="margin-left:auto">${s.everCorrect ? '✓' : '✕'}</span>
      <span class="fav-star${s.fav ? ' on' : ''}" data-fav="${h(q.id)}" title="Favorite">${s.fav ? '★' : '☆'}</span>
    </div>
    <b>${h(q.prompt)}</b>
    <div class="ans">Answer: ${h(answerTextOf(q))}</div>
  </button>`;
}

function bindArchive() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/records'; });
  if (!Entitlement.isClub) return;
  const results = () => $('#archive-results');
  const refresh = () => { const el = results(); if (el) el.innerHTML = archiveResultsHTML(); bindArchiveResults(); };
  const syncURL = () => {
    const qp = new URLSearchParams();
    if (archiveDomain) qp.set('domain', archiveDomain);
    if (archiveFilter === 'fav') qp.set('fav', '1');
    const q = qp.toString();
    history.replaceState(null, '', `#/archive${q ? `?${q}` : ''}`);
  };
  $('#archive-search')?.addEventListener('input', (e) => { archiveText = e.target.value; refresh(); });
  app.querySelectorAll('[data-astatus]').forEach((b) => b.addEventListener('click', () => {
    archiveFilter = b.dataset.astatus === 'all' ? null : b.dataset.astatus;
    app.querySelectorAll('[data-astatus]').forEach((x) => x.classList.toggle('on', x.dataset.astatus === (archiveFilter || 'all')));
    syncURL(); refresh();
  }));
  app.querySelectorAll('[data-adomain]').forEach((b) => b.addEventListener('click', () => {
    archiveDomain = b.dataset.adomain === 'all' ? null : b.dataset.adomain;
    app.querySelectorAll('[data-adomain]').forEach((x) => x.classList.toggle('on', x.dataset.adomain === (archiveDomain || 'all')));
    syncURL(); refresh();
  }));
  bindArchiveResults();
}
function bindArchiveResults() {
  const el = $('#archive-results'); if (!el) return;
  el.querySelectorAll('[data-fav]').forEach((star) => star.addEventListener('click', (e) => {
    e.stopPropagation();
    StoryArchive.toggleFavorite(star.dataset.fav);
    el.innerHTML = archiveResultsHTML();
    bindArchiveResults();
  }));
  el.querySelectorAll('[data-story]').forEach((b) => b.addEventListener('click', () => openStoryDetail(b.dataset.story)));
}

function openStoryDetail(qid) {
  const s = Store.seenStories()[qid];
  if (!s) return;
  const q = s.q, cat = catById(q.categoryID || 'mixed');
  const body = `<h2>${h(q.prompt)}</h2>
    <span class="lvl" style="background:${catColor(cat)}">${h(cat.name)}</span>
    <div class="ans">Answer: ${h(answerTextOf(q))}</div>
    ${q.explanation ? `<p style="margin-top:10px">${h(q.explanation)}</p>` : '<p class="muted" style="margin-top:10px">No story recorded for this one.</p>'}
    <div style="margin-top:14px;display:flex;gap:8px">
      <button type="button" class="btn btn-quiet" data-story-fav>${s.fav ? '★ Favorited' : '☆ Favorite'}</button>
      <button type="button" class="btn btn-primary" data-story-reask>Re-ask this</button>
    </div>`;
  showRecordsSheet(body);
  const dlg = document.getElementById('rec-dlg');
  dlg.querySelector('[data-story-fav]').addEventListener('click', (e) => {
    const fav = StoryArchive.toggleFavorite(qid);
    e.target.textContent = fav ? '★ Favorited' : '☆ Favorite';
    const el = $('#archive-results'); if (el) { el.innerHTML = archiveResultsHTML(); bindArchiveResults(); }
  });
  dlg.querySelector('[data-story-reask]').addEventListener('click', () => {
    dlg.close();
    startGame('classic', catById(q.categoryID || 'mixed'), { custom: [q], label: 'Re-ask' });
  });
}

// Tidbits Club EXCLUSIVE — Marathon (docs/CLUB-FEATURES-BUILD.md "Feature 3"):
// the hub — resume/start-over at the top, the permanent history below. Canonical
// at #/marathon (reachable from the Home card, the post-game scorecard, and
// Records — the web's URL-state superpower).
function viewMarathon() {
  const back = `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
  if (!Entitlement.isClub) {
    return `${back}<h1 class="page-title">Marathon</h1>
      <div class="card pad" style="margin-bottom:14px"><p class="body-strong">${h(Marathon.previewLine())}</p></div>
      <div class="card pad" style="text-align:center">
        <p class="body-strong">A 200-question test of everything, graded by domain.</p>
        <p class="muted">Play it across as many sittings as you like — we keep your place, and every run is measured against your last.</p>
        <a href="#/club" class="btn btn-primary" style="margin-top:12px;display:inline-block;text-decoration:none">Join Tidbits Club</a>
      </div>`;
  }
  const run = Marathon.inProgress();
  const runs = Marathon.history();
  const resumeBlock = run
    ? `<button type="button" class="card pad rec-tap" data-marathon-resume style="margin-bottom:10px">
        <b>Question ${run.currentIndex + 1} of ${run.ids.length}</b><div class="muted">Tap to resume where you left off</div></button>
       <button type="button" class="btn btn-text" data-marathon-startover style="margin-bottom:14px">Start over instead</button>`
    : `<button type="button" class="btn btn-primary btn-full" data-marathon-start style="margin-bottom:14px">Start a Marathon</button>`;
  return `${back}<h1 class="page-title">Marathon</h1>
    <p class="muted">200 questions, graded by domain. Play it across as many sittings as you like.</p>
    ${resumeBlock}
    <h2 class="section">Marathon history</h2>
    ${runs.length ? runs.map((s, i) => marathonHistoryRowHTML(s, i)).join('')
      : '<div class="empty card pad"><p>No Marathons yet — play one across as many sittings as you like, we’ll keep your place.</p></div>'}`;
}

function marathonHistoryRowHTML(s, i) {
  const acc = Math.round(marathonAccuracy(s) * 100);
  return `<button class="card game-row rec-tap" data-marathon-detail="${i}">
    <span class="game-main"><span class="game-head"><b>${s.correct}/${s.total} correct · ${acc}%</b></span>
    <span class="muted game-sub">${h(new Date(s.date).toLocaleDateString())}</span></span>
    <span class="big-sm">${s.score}</span></button>`;
}

function bindMarathon() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.hash = '#/play'; });
  if (!Entitlement.isClub) return;
  $('[data-marathon-start]')?.addEventListener('click', () => startMarathonRound(false));
  $('[data-marathon-resume]')?.addEventListener('click', () => startMarathonRound(false));
  $('[data-marathon-startover]')?.addEventListener('click', () => startMarathonRound(true));
  app.querySelectorAll('[data-marathon-detail]').forEach((b) => b.addEventListener('click', () => openMarathonScoreDetail(Marathon.history()[+b.dataset.marathonDetail])));
}

// "+6% vs your last run" — the measured-mastery payoff (the whole reason
// Marathon isn't just a long Classic). Shared by the live post-game scorecard
// and the history detail sheet.
function marathonCompareHTML(entry, previous) {
  if (!previous) {
    return `<div class="card pad marathon-compare"><div class="body-strong">Your first Marathon</div>
      <div class="muted">Play another to see how you're improving</div></div>`;
  }
  const delta = Math.round((marathonAccuracy(entry) - marathonAccuracy(previous)) * 100);
  const word = delta === 0 ? 'Same as your last run' : `${delta > 0 ? '+' : ''}${delta}% vs your last run`;
  return `<div class="card pad marathon-compare"><div class="body-strong">${h(word)}</div>
    <div class="muted">Last run: ${Math.round(marathonAccuracy(previous) * 100)}% · this run: ${Math.round(marathonAccuracy(entry) * 100)}%</div></div>`;
}

// Per-domain accuracy bars — the measured-mastery map, not just a score.
function marathonDomainRowsHTML(domainBreakdown) {
  const rows = (domainBreakdown || []).filter((d) => d.total > 0);
  if (!rows.length) return '<p class="muted">No domain breakdown recorded.</p>';
  return rows.map((d) => {
    const cat = catById(d.categoryId);
    const pct = d.total ? Math.round((d.correct / d.total) * 100) : 0;
    return `<div class="marathon-domain-row">
      <div class="marathon-domain-head"><span>${h(cat.symbol)} ${h(cat.name)}</span><span class="muted">${d.correct}/${d.total} · ${pct}%</span></div>
      <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, pct)}%;background:${catColor(cat)}"></div></div>
    </div>`;
  }).join('');
}

function marathonDurationLabel(seconds) {
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${Math.max(1, minutes)} min`;
  const hrs = Math.floor(minutes / 60), rem = minutes % 60;
  return rem === 0 ? `${hrs}h` : `${hrs}h ${rem}m`;
}

// A past run's read-only detail — reuses the Records dialog (mirrors
// openStoryDetail/openRecap) rather than a full-page replace.
function openMarathonScoreDetail(entry) {
  if (!entry) return;
  const runs = Marathon.history();
  const idx = runs.findIndex((s) => s.date === entry.date);
  const previous = idx >= 0 ? runs[idx + 1] : null;
  const body = `<h2>${entry.correct}/${entry.total} correct · ${Math.round(marathonAccuracy(entry) * 100)}%</h2>
    <p class="muted">${h(new Date(entry.date).toLocaleDateString())} · ${marathonDurationLabel(entry.durationSeconds)}</p>
    ${marathonCompareHTML(entry, previous)}
    <h3 class="section">Where you stood this run</h3>
    ${marathonDomainRowsHTML(entry.domainBreakdown)}`;
  showRecordsSheet(body);
}

// The Marathon scorecard — a just-completed run's payoff. Unlike renderResults
// (which reads the current session's summary), this reads the permanent
// MarathonScore just written, because a run's true total spans however many
// sessions it took to finish, not just this last one.
function renderMarathonResults(entry) {
  const runs = Marathon.history();
  const previous = runs[1] || null;   // runs[0] is the one we just wrote
  const acc = Math.round(marathonAccuracy(entry) * 100);
  app.innerHTML = `
    <div class="results">
      <div class="card scorecard" style="--tint:#13B6C9">
        <div class="muted">MARATHON COMPLETE</div><div class="huge">${entry.score}</div>
        <div class="muted">${entry.correct}/${entry.total} correct · ${marathonDurationLabel(entry.durationSeconds)}</div>
      </div>
      ${marathonCompareHTML(entry, previous)}
      <div class="stat-row">${statBox(acc + '%', 'Accuracy', '#2D5BFF')}${statBox(entry.score, 'Score', '#13B6C9')}${statBox(runs.length, 'Marathons', '#FF5C5C')}</div>
      <h2 class="section">Where you stood this run</h2>
      ${marathonDomainRowsHTML(entry.domainBreakdown)}
      <button type="button" class="btn btn-text btn-full" data-marathon-history>See Marathon history</button>
      <button class="btn btn-primary btn-full" data-marathon-again>Start a new Marathon</button>
      <button class="btn btn-text btn-full" data-done>Done</button>
    </div>`;
  $('[data-marathon-history]').addEventListener('click', () => { game = null; location.hash = '#/marathon'; });
  $('[data-marathon-again]').addEventListener('click', () => { game = null; startMarathonRound(true); });
  $('[data-done]').addEventListener('click', quitGame);
}

function dailyArchiveRows() {
  const days = [];
  const d = new Date();
  for (let i = 0; i < 30; i++) {
    days.push(dayKey(d));
    d.setDate(d.getDate() - 1);
  }
  const today = dayKey();
  const label = (k) => {
    if (k === today) return 'Today';
    const [y, m, dd] = k.split('-').map(Number);
    return new Date(y, m - 1, dd).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
  };
  return days.map((k) => {
    const sc = Store.dailyScore(k);
    return `<div class="daily-row"><b>${label(k)}</b>${sc != null
      ? `<span class="muted">Scored ${sc}</span>`
      : `<button type="button" class="btn" data-daily-day="${k}">Play</button>`}</div>`;
  }).join('');
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
      <p class="apps-foot muted"><a href="/support.html">Support</a> · <a href="/privacy.html">Privacy</a> · <a href="/refunds.html">Refunds</a> · tidbitstrivia.com</p>
    </section>`;
}

let custModes = ['classic'];
let custCat = 'mixed';
let custShowAll = false;

function renderCustModes() {
  const list = custShowAll ? ALL_MODES : CORE_MODES;
  const box = $('#cust-modes');
  box.innerHTML = list.map((m) => `<button type="button" class="chip${custModes.includes(m) ? ' on' : ''}" data-cmode="${m}">${h(MODES[m].title)}</button>`).join('');
  // Multi-select: tap toggles; the last selected can't be removed.
  box.querySelectorAll('[data-cmode]').forEach((b) => b.addEventListener('click', () => {
    const m = b.dataset.cmode;
    if (custModes.includes(m)) { if (custModes.length > 1) custModes = custModes.filter((x) => x !== m); }
    else custModes = ALL_MODES.filter((x) => custModes.includes(x) || x === m);
    renderCustModes();
    markCustCat();   // which categories a mode can fill changes with the mode
  }));
  const more = $('[data-more-modes]'); if (more) more.textContent = custShowAll ? 'Show fewer modes' : 'Show all modes';
  // One mode shows its blurb; several explain the mix.
  const blurb = $('#cust-blurb');
  if (blurb) blurb.textContent = custModes.length === 1
    ? `${MODES[custModes[0]].title}: ${MODES[custModes[0]].blurb}`
    : `Custom Mix: questions drawn from all ${custModes.length} selected modes, shuffled together.`;
  const startBtn = $('[data-cust-start]');
  if (startBtn) startBtn.textContent = custModes.length > 1 ? `Start the Mix (${custModes.length})` : 'Start';
}
// Which bundled set a mode draws from, or null when it rides the corpus.
// Mirrors Swift `QuestionProvider.source(for:)`.
function modeSource(modeID) {
  return { pictureId: Pictures, thisOrThat: ThisOrThat, closestCall: ClosestCall,
           ordering: Ordering, matching: Matching, typeAnswer: TypeAnswer,
           oddOneOut: OddOneOut, enumerate: Enumerate }[modeID] || null;
}

// Can a round of this mode actually be filled from this category? False means it
// will be assembled from OTHER categories — Business has zero rows in every
// bundled shape set, so Business + Picture ID is a round with no business in it.
// Mirrors Swift `QuestionProvider.canFill(mode:categoryID:)`.
function canFillCat(modeID, catID) {
  if (catID === 'mixed') return true;
  const mode = MODES[modeID];
  if (!mode) return true;
  const src = modeSource(modeID);
  const have = src ? src.countIn(catID) : Corpus.countIn(catID);
  return have >= mode.count;
}

function markCustCat() {
  // Any picked mode that can fill it is enough — a Custom Mix spans several.
  const modes = custModes.length ? custModes : ['classic'];
  $('#cust-cats').querySelectorAll('[data-ccat]').forEach((c) => {
    c.classList.toggle('on', c.dataset.ccat === custCat);
    // Dimmed, not disabled: the round still plays, it just is not the category
    // you asked for, and removing the choice is worse than telling the truth.
    c.classList.toggle('thin', !modes.some((m) => canFillCat(m, c.dataset.ccat)));
  });
  const note = $('#cust-cat-note');
  if (note) {
    const ok = modes.some((m) => canFillCat(m, custCat));
    note.textContent = ok ? ''
      : `${catById(custCat).name} has no questions for this mode yet — you'll get a mixed round.`;
    note.hidden = ok;
  }
}
function renderCustPresets() {
  const ps = getPresets();
  const el = $('#cust-presets');
  el.innerHTML = ps.length ? `<h3 class="section">My presets</h3><div class="chips">${ps.map((p, i) => `<button type="button" class="chip" data-preset-idx="${i}">${h(p.name)}</button>`).join('')}</div>` : '';
  el.querySelectorAll('[data-preset-idx]').forEach((b) => b.addEventListener('click', () => {
    const p = getPresets()[+b.dataset.presetIdx]; if (!p) return;
    custModes = p.mode === 'mix' && p.modeIds && p.modeIds.length ? p.modeIds.filter((m) => MODES[m]) : [p.mode];
    if (!custModes.length) custModes = ['classic'];
    if (!custModes.every((m) => CORE_MODES.includes(m))) custShowAll = true;
    custCat = (p.categoryIds && p.categoryIds[0]) || 'mixed';
    renderCustModes(); markCustCat();
  }));
}

function bindHome() {
  // Quick Play — ONE action, one target (R-HOME-1a); Surprise is its own button.
  $('[data-quickplay]').addEventListener('click', () => {
    const qp = quickPlayTarget();
    if (qp.mode === 'mix') {
      const modes = lastMixModes();
      if (modes.length >= 2) { startMixOrSingle(modes, qp.cat); return; }
      startGame('classic', catById(qp.cat)); return;
    }
    rememberPlay(qp.mode, qp.cat); startGame(qp.mode, catById(qp.cat));
  });
  $('[data-surprise]').addEventListener('click', () => {
    const m = ALL_MODES[Math.floor(Math.random() * ALL_MODES.length)];
    const c = CATEGORIES[Math.floor(Math.random() * CATEGORIES.length)];
    rememberPlay(m, c.id); startGame(m, catById(c.id));
  });
  // Daily is play-once (R-DAILY-1): once done, the card opens the archive.
  const dailyDlg = $('#daily-dlg');
  $('[data-daily]').addEventListener('click', () => {
    if (Store.dailyScore(dayKey()) != null) dailyDlg.showModal();
    else startGame('daily', catById('mixed'));
  });
  $('[data-daily-close]').addEventListener('click', () => dailyDlg.close());
  $('[data-daily-board]')?.addEventListener('click', (ev) => { ev.stopPropagation(); location.hash = '#/dailyboard'; });
  // Online Multiplayer (Decision 038): v0 = Play vs CPU; Quick Match = honest v1 slot.
  const mpDlg = $('#mp-dlg');
  $('[data-multiplayer]').addEventListener('click', () => mpDlg.showModal());
  $('[data-mp-close]').addEventListener('click', () => mpDlg.close());
  mpDlg.querySelectorAll('[data-bot]').forEach((b) => b.addEventListener('click', () => {
    mpDlg.close();
    startGame('classic', catById('mixed'), { versusBot: b.dataset.bot });
  }));
  const qm = $('[data-quickmatch]');
  if (qm) qm.addEventListener('click', () => { mpDlg.close(); OnlineMatch.start(); });
  dailyDlg.querySelectorAll('[data-daily-day]').forEach((b) => b.addEventListener('click', () => {
    dailyDlg.close();
    startGame('daily', catById('mixed'), { dailyDay: b.dataset.dailyDay });
  }));

  // Trivia Night dialog (native <dialog showModal> — focus trap + ESC free).
  let nightPreset = 1;
  const dlg = $('#night-dlg');
  $('[data-night-open]').addEventListener('click', () => dlg.showModal());
  $('[data-live-join]').addEventListener('click', () => { dlg.close(); location.hash = '#/live'; });
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
  $('[data-night-host]').addEventListener('click', () => {
    const catId = $('#night-cat').value;
    const preset = NIGHT.presets[nightPreset];
    dlg.close();
    openNightHost({ rounds: preset.rounds }, catById(catId));
  });

  // Customize dialog (mode + category + presets, one Start).
  const cust = $('#customize-dlg');
  const qp = quickPlayTarget();
  custModes = qp.mode === 'mix' ? (lastMixModes().length ? lastMixModes() : ['classic']) : [qp.mode];
  custCat = qp.cat; custShowAll = !custModes.every((m) => CORE_MODES.includes(m));
  renderCustModes(); renderCustPresets(); markCustCat();
  $('[data-customize]').addEventListener('click', () => { renderCustModes(); renderCustPresets(); markCustCat(); cust.showModal(); });
  $('[data-more-modes]').addEventListener('click', () => { custShowAll = !custShowAll; renderCustModes(); });
  $('#cust-cats').querySelectorAll('[data-ccat]').forEach((b) => b.addEventListener('click', () => { custCat = b.dataset.ccat; markCustCat(); }));
  $('[data-cust-start]').addEventListener('click', () => { cust.close(); startMixOrSingle(custModes, custCat); });
  $('[data-cust-save]').addEventListener('click', () => {
    const def = custModes.length === 1
      ? `${(catById(custCat) || { name: '' }).name} ${MODES[custModes[0]].title}`
      : `${(catById(custCat) || { name: '' }).name} Mix`;
    const name = prompt('Name this preset', def);
    if (name && name.trim()) {
      savePreset({ name: name.trim(), mode: custModes.length === 1 ? custModes[0] : 'mix',
        categoryIds: [custCat], modeIds: custModes });
      renderCustPresets();
    }
  });
}

// ---------------- Create ----------------
function viewCreate() {
  const sugg = ['The Solar System', 'Ancient Rome', 'Jazz', 'Volcanoes', 'The Olympics', 'Marie Curie'];
  const saved = allQuizzes();
  return `
    <h1 class="page-title">Create a quiz</h1>
    <p class="muted">Pick any subject. We'll pull a varied set — different kinds of questions across categories — from the corpus and Wikipedia.</p>
    <div class="card pad">
      <input id="topic" class="input" placeholder="e.g. The Renaissance" autocomplete="off">
      <label class="muted" for="create-mode" style="display:block;margin:10px 0 4px">Play it as</label>
      <select id="create-mode" class="input">${PLAYABLE_MODES.map((m) => `<option value="${m}">${h(MODE_LABELS[m])}</option>`).join('')}</select>
      <button id="gen" class="btn btn-grape btn-full">Generate Quiz</button>
      <div id="create-err" class="error" hidden></div>
    </div>
    <h2 class="section">Need a spark?</h2>
    <div class="chips wrap">${sugg.map((s) => `<button class="chip" data-sugg="${h(s)}">${h(s)}</button>`).join('')}</div>
    <h2 class="section">Your quizzes</h2>
    ${saved.length
      ? `<div class="saved-sets">${saved.map((q) => `<div class="card saved-set">
        <button class="saved-play" data-play-quiz="${h(q.id)}"><b>${h(q.title)}</b><span class="muted">${q.entries.length} questions · saved ${new Date(q.createdAt).toLocaleDateString()}</span></button>
        <button class="saved-share icon-btn" data-share-quiz="${h(q.id)}" aria-label="Share quiz">↗</button>
        <button class="saved-del icon-btn" data-del-quiz="${h(q.id)}" aria-label="Delete quiz">✕</button>
      </div>`).join('')}</div>`
      : `<p class="muted">Quizzes you make are saved here automatically, ready to replay.</p>`}`;
}
// Build a varied Create set (owner: multiple modes AND categories, not 8
// near-identical questions). Diversity-capped MCQ from the corpus + a couple of
// topic-matched OTHER shapes (picture / this-or-that / closest) so the quiz
// mixes question types. Falls back to live Wikipedia only when the corpus is thin.
async function buildCreateSet(topic) {
  const shaped = [];
  for (const src of [Pictures, ThisOrThat, ClosestCall]) {
    try { shaped.push(...await src.searchMatch(topic, 1)); } catch { /* source optional */ }
  }
  const mcqNeeded = Math.max(4, 8 - shaped.length);
  await Corpus.loadFull();   // search reads every prompt
  const mcq = Corpus.search(topic, mcqNeeded);
  let set = [...mcq, ...shaped];
  if (set.length < 8) {
    // Top up rather than only rescuing a near-total miss. Live generation used to
    // fire ONLY when the corpus returned fewer than three, so a topic with six
    // silently delivered six — every thin topic in coverage.py sat in that band.
    const have = new Set(set.map((q) => q.id));
    const gen = await Wikipedia.generate(topic, 'mixed', 8 - set.length + 2);
    set = set.concat(gen.filter((q) => !have.has(q.id)));
  }
  set = set.slice(0, 8);
  for (let i = set.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [set[i], set[j]] = [set[j], set[i]]; }
  return set;
}

function bindCreate() {
  const run = async () => {
    const topic = $('#topic').value.trim();
    if (topic.length < 2) return;
    const err = $('#create-err'); err.hidden = true;
    const btn = $('#gen'); btn.textContent = 'Building your quiz…'; btn.disabled = true;
    try {
      const qs = await buildCreateSet(topic);
      if (qs.length >= 3) {
        // Every created quiz is saved automatically — the player never has to
        // notice a Save button to keep what they made.
        const mode = ($('#create-mode') || {}).value || 'mix';
        const quiz = saveCreated({ questions: qs, topic, creatorID: 'local', creatorName: '', mode });
        startGame(mode, catById('mixed'), { custom: qs, label: topic, quizID: quiz.id });
      } else { err.textContent = `Couldn't build a good quiz for “${topic}”. Try a broader or more famous subject.`; err.hidden = false; }
    } catch { err.textContent = 'Network trouble reaching Wikipedia. Try again.'; err.hidden = false; }
    btn.textContent = 'Generate Quiz'; btn.disabled = false;
  };
  $('#gen').addEventListener('click', run);
  $('#topic').addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
  app.querySelectorAll('[data-sugg]').forEach((b) =>
    b.addEventListener('click', () => { $('#topic').value = b.dataset.sugg; run(); }));
  app.querySelectorAll('[data-play-quiz]').forEach((b) =>
    b.addEventListener('click', () => {
      const quiz = getQuiz(b.dataset.playQuiz); if (!quiz) return;
      // A quiz can legitimately come up short (an older corpus, a set this build
      // lacks), so say so rather than silently padding it with other questions.
      const r = resolveForPlay(quiz);
      if (!r.isPlayable) {
        const err = $('#create-err');
        err.textContent = `This quiz needs questions your version doesn't have yet. Try creating it again from “${quiz.topic}”.`;
        err.hidden = false;
        return;
      }
      // A quiz saved as Survival must replay as Survival — the mode was recorded
      // and then ignored before this.
      startGame(playableMode(quiz.mode), catById('mixed'), { custom: r.questions, label: quiz.title, quizID: quiz.id });
    }));
  app.querySelectorAll('[data-share-quiz]').forEach((b) =>
    b.addEventListener('click', () => {
      const quiz = getQuiz(b.dataset.shareQuiz); if (quiz) shareQuiz(quiz, b);
    }));
  app.querySelectorAll('[data-del-quiz]').forEach((b) =>
    b.addEventListener('click', () => { deleteQuiz(b.dataset.delQuiz); render(); }));
}


// ---- A shared quiz (#/quiz/<id>) ----
// Every state here is a real state, not an afterthought (universal-feature-states):
// loading, not-found, too-few-questions-in-this-build, and playable-but-short each
// say something true rather than showing a blank card.
/**
 * The landing twin for a shared question (DEEP_LINKS.md "canonical-twin rule").
 *
 * It shows the FACT, not the quiz: someone arriving here was sent a thing worth
 * knowing by a friend, and making them guess it first would be a puzzle they did not
 * ask for and cannot lose gracefully. The answer, the explanation and the door out to
 * the source are the payload; playing is the invitation underneath it.
 */
async function openSharedItem(id) {
  if (!id) { location.hash = '#/'; return; }
  renderLoading('Opening…');
  const found = await lookupSharedItem(id);
  if (!found) {
    app.innerHTML = `${header(currentTab())}<main class="main"><div class="view">
      <h1 class="page-title">Not found</h1>
      <p class="muted">This link doesn\u2019t point at a question any more \u2014 it may have been retired from the bank since it was shared.</p>
      <button class="btn btn-primary btn-full" data-play-any>Play Tidbits</button>
    </div></main>`;
    $('[data-play-any]').addEventListener('click', () => { location.hash = '#/'; });
    document.title = 'Tidbits Trivia';
    return;
  }
  const q = found;
  const answer = (q.options && q.options[q.correctIndex]) || q.answer || '';
  const cat = catById(q.categoryID);
  // Keeps the app header: a stranger who followed this link has nowhere else to go
  // otherwise, and the nav IS the invitation.
  app.innerHTML = `${header(currentTab())}<main class="main"><div class="view">
    <p class="muted" style="text-transform:uppercase;letter-spacing:.06em;font-weight:800;font-size:.75rem">
      ${h(cat ? cat.name : 'Tidbits')}</p>
    <h1 class="page-title" style="margin-top:2px">${h(q.prompt)}</h1>
    <div class="card pad" style="margin-top:14px">
      <div class="muted" style="font-size:.75rem;font-weight:800;letter-spacing:.06em">ANSWER</div>
      <div style="font-weight:900;font-size:1.4rem;margin:2px 0 10px">${h(answer)}</div>
      ${q.explanation ? `<p class="body" style="margin:0">${h(q.explanation)}</p>` : ''}
      ${q.sourceURL ? `<p style="margin:12px 0 0"><a href="${h(q.sourceURL)}" target="_blank" rel="noopener">Read on Wikipedia \u2197</a></p>` : ''}
    </div>
    <button class="btn btn-primary btn-full" style="margin-top:16px" data-play-item>Play Tidbits</button>
    <button class="btn btn-text btn-full" data-copy-item>Copy link</button>
  </div></main>`;
  $('[data-play-item]').addEventListener('click', () => { location.hash = '#/'; });
  $('[data-copy-item]').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(itemURL(q.id)); toast('Link copied'); } catch { toast('Copy failed'); }
  });
  document.title = `${q.sourceTitle || 'Tidbits Trivia'} — Tidbits`;
}

// An id can live in the corpus or in any bundled shape set, and the shards mean the
// corpus in memory is a SAMPLE — so a miss has to fall back to the full file before it
// is reported as "retired", or a perfectly good link would 404 on a stratified shard.
async function lookupSharedItem(id) {
  // The prefix usually names the set outright — ask that one first so a shape link never
  // waits on the corpus. `src:` is absent on purpose: Picture ID shares that namespace.
  const byPrefix = {
    tot: ThisOrThat, biztot: ThisOrThat, odd: OddOneOut, oddrel: OddOneOut,
    closest: ClosestCall, order: Ordering, bizorder: Ordering,
    match: Matching, type: TypeAnswer, enum: Enumerate, enumrel: Enumerate,
  }[(id || '').split(':')[0]];
  if (byPrefix) {
    try { await byPrefix.load(); } catch {}
    const q = byPrefix.question?.(id);
    if (q) return q;
  }
  const sets = [Corpus, Pictures, ThisOrThat, ClosestCall, Ordering, Matching, TypeAnswer, OddOneOut, Enumerate];
  for (const s of sets) {
    try { await s.load(); } catch {}
    const q = s.question?.(id);
    if (q) return q;
  }
  // A corpus id can be outside the loaded shard, so a miss falls back to the full file
  // before it is reported as retired — otherwise a perfectly good link 404s on a shard.
  try { await Corpus.loadFull(); } catch { return null; }
  return Corpus.question(id) || null;
}

/** The canonical shape from DEEP_LINKS.md — every platform's per-question share uses it. */
function itemURL(id) { return `${SITE_URL}/item/${encodeURIComponent(id)}`; }

/**
 * First-run walkthrough (PARITY: "3-card play/learn/compete"). The same three cards as
 * iOS + Android, in the web's own idiom: a native `<dialog showModal>` — focus trap and
 * ESC for free (CLAUDE.md "modern web APIs first"), not a hand-rolled overlay.
 *
 * The order is deliberate and matches the native copy: play, then LEARN, then compete.
 * Learning is the point, not a side effect.
 */
const ONBOARDED_KEY = 'tidbits.onboarded';
const ONBOARD_SLIDES = [
  { icon: '🌍', color: 'var(--color-accent)', title: 'All of Wikipedia, as trivia',
    body: "Thousands of questions built from real Wikipedia facts — and you can spin up a quiz on any topic you like." },
  { icon: '💡', color: '#FFC93C', title: 'Learn something every round',
    body: "Miss one? We show you the fact and the article. Missed questions quietly come back so they actually stick." },
  { icon: '🎉', color: '#8B5CF6', title: 'Solo or together',
    body: "Chase your own best score, keep a daily streak, or share a quiz with a friend." },
];

function maybeShowOnboarding() {
  if (localStorage.getItem(ONBOARDED_KEY) === '1') return;
  // Never in front of a shared link: someone arriving on a quiz or an item was sent
  // somewhere specific, and a walkthrough in the way is a toll booth.
  if (location.hash.startsWith('#/quiz/') || location.hash.startsWith('#/item/')
      || location.hash.startsWith('#/live')) return;
  let page = 0;
  const dlg = document.createElement('dialog');
  dlg.className = 'night-dlg';
  dlg.id = 'onboard-dlg';
  document.body.appendChild(dlg);

  const paint = () => {
    const s = ONBOARD_SLIDES[page];
    const last = page === ONBOARD_SLIDES.length - 1;
    dlg.innerHTML = `<div class="night-form" style="text-align:center;gap:16px">
      <div aria-hidden="true" style="font-size:44px;line-height:1;width:104px;height:104px;margin:6px auto 0;
        display:flex;align-items:center;justify-content:center;border-radius:999px;
        background:${s.color};border:4px solid var(--color-border)">${s.icon}</div>
      <h2 style="font-size:1.5rem">${h(s.title)}</h2>
      <p class="body" style="color:var(--color-ink);opacity:.75">${h(s.body)}</p>
      <div aria-hidden="true" style="display:flex;gap:8px;justify-content:center">${
        ONBOARD_SLIDES.map((_, i) => `<span style="width:9px;height:9px;border-radius:999px;background:${
          i === page ? 'var(--color-primary)' : 'var(--color-border)'};opacity:${i === page ? 1 : .3}"></span>`).join('')}</div>
      <button class="btn btn-primary btn-full" data-onboard-next>${last ? 'Start Playing' : 'Next'}</button>
      ${last ? '' : '<button class="btn btn-text btn-full" data-onboard-skip>Skip</button>'}
    </div>`;
    dlg.querySelector('[data-onboard-next]').addEventListener('click', () => {
      if (last) finish(); else { page++; paint(); }
    });
    dlg.querySelector('[data-onboard-skip]')?.addEventListener('click', finish);
  };
  const finish = () => {
    localStorage.setItem(ONBOARDED_KEY, '1');
    dlg.close();
    dlg.remove();
  };
  // ESC closes a native dialog, and a walkthrough dismissed that way is still done —
  // re-showing it on the next load would be nagging, not helpfulness.
  dlg.addEventListener('close', () => { localStorage.setItem(ONBOARDED_KEY, '1'); dlg.remove(); });
  paint();
  dlg.showModal();
}

async function openSharedQuiz(id) {
  if (!id) { location.hash = '#/create'; return; }
  renderLoading('Opening quiz…');
  const res = await fetchSharedQuiz(id);
  // "Deleted" and "couldn't load" need DIFFERENT words: telling someone with a
  // working link that the quiz is gone stops them retrying a transient failure.
  if (res.notFound || res.error) {
    app.innerHTML = `<div class="view">
      <h1 class="page-title">${res.notFound ? 'Quiz not found' : 'Couldn\u2019t open this quiz'}</h1>
      <p class="muted">${res.notFound
        ? "This link doesn't point at a quiz any more. It may have been deleted by whoever made it."
        : h(res.error)}</p>
      ${res.error ? '<button class="btn btn-primary btn-full" data-retry>Try again</button>' : ''}
      <button class="btn ${res.error ? '' : 'btn-primary'} btn-full" data-make>Make your own quiz</button>
    </div>`;
    const retry = $('[data-retry]');
    if (retry) retry.addEventListener('click', () => openSharedQuiz(id));
    $('[data-make]').addEventListener('click', () => { location.hash = '#/create'; });
    return;
  }
  const quiz = res.quiz;
  const r = resolveForPlay(quiz);
  const short = r.missing > 0;
  app.innerHTML = `<div class="view">
    <h1 class="page-title">${h(quiz.title)}</h1>
    <p class="muted">${quiz.creatorName ? `Made by ${h(quiz.creatorName)} · ` : ''}${quiz.entries.length} questions</p>
    ${short ? `<div class="card pad"><p class="muted">${r.missing} of these ${quiz.entries.length} questions aren't in your version yet, so you'll play ${r.questions.length}.</p></div>` : ''}
    ${r.isPlayable
      ? `<button class="btn btn-primary btn-full" data-play-shared>Play this quiz</button>
         <button class="btn btn-full" data-keep>Save to my quizzes</button>`
      : `<div class="card pad"><p class="muted">This quiz needs questions your version doesn't have yet. Try making one on the same subject instead.</p></div>
         <button class="btn btn-primary btn-full" data-remake>Make a quiz about ${h(quiz.topic || 'this')}</button>`}
    <button class="btn btn-text btn-full" data-done>Back</button>
  </div>`;
  const play = $('[data-play-shared]');
  if (play) play.addEventListener('click', () => {
    keepSharedQuiz(quiz);            // playing it is keeping it
    startGame('mix', catById('mixed'), { custom: r.questions, label: quiz.title, quizID: quiz.id });
  });
  const keep = $('[data-keep]');
  if (keep) keep.addEventListener('click', () => {
    keepSharedQuiz(quiz); keep.textContent = 'Saved ✓'; keep.disabled = true;
  });
  const remake = $('[data-remake]');
  if (remake) remake.addEventListener('click', () => {
    location.hash = '#/create';
    setTimeout(() => { const t = $('#topic'); if (t) { t.value = quiz.topic || ''; } }, 50);
  });
  $('[data-done]').addEventListener('click', () => { location.hash = '#/create'; });
}

// Share a quiz: publish it, then hand over the link. Web Share where available,
// clipboard otherwise — the same fallback chain the rest of the app uses.
async function shareQuiz(quiz, btn) {
  const label = btn.textContent;
  btn.textContent = 'Sharing…'; btn.disabled = true;
  try {
    const url = await publishQuiz(quiz);
    const text = `${quiz.title} — a Tidbits quiz`;
    if (navigator.share) { await navigator.share({ title: quiz.title, text, url }); }
    else { await navigator.clipboard.writeText(url); }
    btn.textContent = navigator.share ? label : 'Link copied ✓';
  } catch (e) {
    // A share that silently does nothing is worse than one that admits it failed.
    btn.textContent = 'Couldn\u2019t share — try again';
    console.warn('[Tidbits] share failed', e);
  }
  btn.disabled = false;
  setTimeout(() => { btn.textContent = label; }, 2500);
}

// ---- Saved quizzes ----
// The pre-contract `tidbits.savedSets` helpers are GONE. They stored full question
// text keyed by a label, web-only and unshareable; js/quizstore.js replaces them and
// migrateLegacySavedSets() converts anything a returning player already had
// (docs/QUIZ-CONTRACT.md §7). Nothing may write that key again — a writer left
// behind would keep resurrecting the old format on every render.

// Canonical cross-platform wire question (matches Android WireQuestion + the
// night wire): categoryId / sourceUrl / imageUrl casing, so a web-hosted online
// match decodes on Android and vice versa.
function toWire(q) {
  return {
    id: q.id, prompt: q.prompt, options: q.options || [], correctIndex: q.correctIndex || 0,
    categoryId: q.categoryID || 'mixed', difficulty: q.difficulty || 3, explanation: q.explanation || '',
    sourceTitle: q.sourceTitle || '', sourceUrl: q.sourceURL || '', imageUrl: q.image || null,
    closest: q.closest || null, ordering: q.ordering || null, matching: q.matching || null,
    accepted: q.accepted || null, enumerate: q.enumerate || null, roundIndex: q.roundIndex ?? null,
  };
}
function fromWire(w) {
  if (!w || !w.id) return null;
  return {
    id: w.id, prompt: w.prompt, options: w.options || [], correctIndex: w.correctIndex || 0,
    categoryID: w.categoryId || 'mixed', difficulty: w.difficulty || 3, explanation: w.explanation || '',
    sourceTitle: w.sourceTitle || '', sourceURL: w.sourceUrl || '', image: w.imageUrl || null,
    closest: w.closest || null, ordering: w.ordering || null, matching: w.matching || null,
    accepted: w.accepted || null, enumerate: w.enumerate || null, roundIndex: w.roundIndex ?? null,
  };
}

// ---------------- Online Quick Match (Firebase RTDB, Decision 040) ----------------
// Same-questions race: a leader builds the set + writes it to the room; every
// device plays it locally and self-reports its score; live standings from the
// roster; best score wins. Trust model = local Trivia Night (room-gated,
// self-scored). Apple uses GameKit instead (Decision 039).
const OnlineMatch = {
  roomId: null, isLeader: false, unsubRoster: null, unsubMeta: null, players: {}, meta: {},
  name: (localStorage.getItem('tidbits.night.lastName') || 'Player'),

  async start() {
    render(); // clear
    renderLoading('Finding a match…');
    try {
      const res = await FirebaseNet.quickMatch(this.name, { onError: (m) => { this._fail(m); } });
      if (!res) return;
      this.roomId = res.roomId; this.isLeader = res.isLeader;
      this._listen();
      this.renderLobby();
    } catch (e) { /* onError already rendered */ }
  },

  _listen() {
    this.unsubRoster = FirebaseNet.onRoster(this.roomId, (p) => {
      this.players = p || {};
      if (game && game._online) renderGame();           // live standings during play
      else if (!this.meta.state || this.meta.state === 'lobby') this.renderLobby();
      else if (this.meta.state === 'finished') this.renderStandings();
    });
    this.unsubMeta = FirebaseNet.onMeta(this.roomId, async (m) => {
      this.meta = m || {};
      if (this.meta.state === 'playing' && (!game || !game._online)) await this._play();
      else if (this.meta.state === 'finished' && (!game || game.phase !== 'finished')) this.renderStandings();
    });
  },

  async _startAsLeader() {
    // Build a shared 8-question set and publish it in the CANONICAL wire shape
    // (field names matching Android's WireQuestion) so a web-hosted match
    // decodes on Android and vice versa — same contract as the night wire.
    let qs = Corpus.pull('mixed', new Set(), 8);
    if (!qs || qs.length < 5) qs = Corpus.pull('mixed', new Set(), 8);
    await FirebaseNet.setMeta(this.roomId, { state: 'playing', startedAt: Date.now(), questions: JSON.stringify(qs.map(toWire)) });
  },

  async _play() {
    let wire = [];
    try { wire = JSON.parse(this.meta.questions || '[]'); } catch { wire = []; }
    const qs = wire.map(fromWire).filter(Boolean);
    if (!qs.length) return;
    startGame('mix', catById('mixed'), { custom: qs, label: 'Online Match', online: this });
  },

  reportProgress(score, done) {
    if (this.roomId) FirebaseNet.reportScore(this.roomId, score, done).catch(() => {});
    if (done && this.isLeader) FirebaseNet.setMeta(this.roomId, { state: 'finished' }).catch(() => {});
  },

  leave() {
    if (this.unsubRoster) this.unsubRoster();
    if (this.unsubMeta) this.unsubMeta();
    if (this.roomId) FirebaseNet.leave(this.roomId);
    this.roomId = null; this.isLeader = false; this.players = {}; this.meta = {};
    if (game) { clearInterval(game.timer); game = null; }
    render();
  },

  _roster() {
    return Object.entries(this.players).map(([uid, p]) => ({ uid, me: uid === FirebaseNet.uid, ...p }))
      .sort((a, b) => (b.score || 0) - (a.score || 0));
  },

  renderLobby() {
    const roster = this._roster();
    const enough = roster.length >= 2;
    app.innerHTML = `<div class="online-lobby">
      <h1 class="page-title">Online Match</h1>
      <p class="muted">${enough ? 'Ready when you are.' : 'Waiting for another player to join…'}</p>
      <div class="card pad"><div class="muted">ROOM CODE</div><div class="big-sm">${h(this.roomId)}</div>
        <p class="muted">Share this code for a friend to join, or wait for a random opponent.</p></div>
      <h2 class="section">${roster.length} in the room</h2>
      ${roster.map((r) => `<div class="card row"><b>${h(r.name || 'Player')}${r.me ? ' (you)' : ''}</b></div>`).join('')}
      ${this.isLeader ? `<button class="btn btn-primary btn-full" data-start ${enough ? '' : 'disabled'}>Start the Match</button>`
                      : `<div class="card row muted">Waiting for the host to start…</div>`}
      <button class="btn btn-text btn-full" data-leave>Leave</button>
    </div>`;
    const st = $('[data-start]'); if (st) st.addEventListener('click', () => this._startAsLeader());
    $('[data-leave]').addEventListener('click', () => this.leave());
  },

  renderStandings() {
    if (this.unsubMeta) { /* keep roster live */ }
    const roster = this._roster();
    const top = roster[0];
    const meScore = (this.players[FirebaseNet.uid] || {}).score || 0;
    const won = top && top.uid === FirebaseNet.uid;
    app.innerHTML = `<div class="results">
      <h1 class="page-title">${won ? 'You won! 🎉' : (top ? h(top.name || 'Opponent') + ' takes it' : 'Match over')}</h1>
      ${roster.map((r, i) => `<div class="card vs-standing ${i === 0 ? 'win' : ''}"><b>${h(r.name || 'Player')}${r.me ? ' (you)' : ''}</b><span class="vs-score">${r.score || 0}</span></div>`).join('')}
      <button class="btn btn-primary btn-full" data-again>New Match</button>
      <button class="btn btn-text btn-full" data-done>Done</button>
    </div>`;
    $('[data-again]').addEventListener('click', () => { this.leave(); OnlineMatch.start(); });
    $('[data-done]').addEventListener('click', () => this.leave());
  },

  _fail(msg) {
    app.innerHTML = `<div class="online-lobby"><h1 class="page-title">Couldn't start online play</h1>
      <p class="muted">${h(msg)}</p><button class="btn btn-primary btn-full" data-done>Back</button></div>`;
    $('[data-done]').addEventListener('click', () => this.leave());
  },
};
window.OnlineMatch = OnlineMatch;

// ---------------- Records ----------------
function settingsSection() {
  const on = Store.reviewEnabled();
  return `<h2 class="section">Settings</h2>
    <label class="card row review-toggle"><span><b>Review questions</b><div class="muted">Re-ask questions you've missed, spaced out, so they stick. Off = only new questions.</div></span>
      <input type="checkbox" id="review-toggle" ${on ? 'checked' : ''}></label>
    ${reminderToggle()}`;
}

// The in-app opt-out push needs to have (App Store 4.5.4's rule, and plain courtesy on the
// web). Hidden entirely where it cannot work — an unsupported browser or an unconfigured
// VAPID key would otherwise render a switch that silently does nothing.
function reminderToggle() {
  if (!Push.supported || !Push.configured) return '';
  const denied = Push.permission === 'denied';
  return `<label class="card row review-toggle"><span><b>Daily reminder</b><div class="muted">${
    denied ? 'Blocked in your browser settings — turn notifications back on for this site first.'
           : 'One notification a day, only if you haven\'t played your Daily yet.'}</div></span>
    <input type="checkbox" id="reminder-toggle" ${denied ? 'disabled' : ''}></label>`;
}
function profileCard() {
  const p = Identity.profile;
  const av = (hue, inner) => `<div style="width:44px;height:44px;border-radius:999px;background:hsl(${hue} 55% 72%);border:2.5px solid #231E1A;display:flex;align-items:center;justify-content:center;font-weight:900;color:#231E1A;flex:none">${inner}</div>`;
  const body = p
    ? `${av(avatarHue(p.avatarSeed), h(initialsOf(p.name)))}<div style="flex:1"><b>${h(p.name)}</b><div class="muted" style="font-size:.8rem">Rating ${Math.round(p.rating.value)} · ${p.streak.current}-day streak</div></div>`
    : `${av(210, '')}<div style="flex:1"><b>Your Profile</b></div>`;
  return `<a href="#/profile" class="card pad" style="display:flex;align-items:center;gap:12px;text-decoration:none;color:inherit;margin-bottom:14px">${body}<span class="chev">›</span></a>`;
}

// Wave E: the cross-venue / season leaderboard, read from the static JSON the hourly cron
// commits to data/leaderboard/ — free/cacheable, never RTDB.
// L3 seasons: friendly display + the fresh-start countdown (calendar quarters, matching Core currentSeason).
function seasonDisplay(key) {
  const m = /^(\d{4})-S(\d)$/.exec(key || '');
  return m ? `Q${m[2]} ${m[1]}` : (key || 'Season');
}
function seasonMeta() {
  const now = new Date();
  const q = Math.floor(now.getMonth() / 3) + 1;
  const nextStart = new Date(now.getFullYear(), q * 3, 1);   // first day of the next quarter
  const days = Math.max(0, Math.ceil((nextStart - now) / 86400000));
  return { key: `${now.getFullYear()}-S${q}`, name: `Q${q} ${now.getFullYear()}`, days };
}

function viewLeaderboard() {
  return `<div style="max-width:640px;margin:0 auto;padding:8px 4px">
    <a href="#/records" style="color:var(--color-accent);text-decoration:none;font-weight:700">‹ Records</a>
    <h1 class="view-heading">Leaderboard</h1>
    <p class="body">Season standings across every venue where you've played a live Tidbits night.</p>
    <div id="lb-body"><p class="body">Loading…</p></div>
  </div>`;
}
async function loadLeaderboard() {
  const body = document.getElementById('lb-body');
  if (!body) return;
  const e = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const myUid = Identity.authUid;   // Wave E: defendable titles — mark the champion + your own row
  const table = (rows) => (!rows || !rows.length)
    ? `<p class="body" style="opacity:.55">No standings yet.</p>`
    : `<div style="display:flex;flex-direction:column;gap:6px;margin:8px 0 20px">` + rows.slice(0, 25).map((r, i) => {
        const me = !!(r.uid && r.uid === myUid);
        return `<div style="display:flex;align-items:center;gap:10px;padding:10px 14px;border-radius:12px;background:var(--color-surface);${me ? 'outline:2px solid var(--color-accent);outline-offset:-2px' : ''}">
           <span style="font-weight:900;width:28px;opacity:${i === 0 ? 1 : 0.5}">${i + 1}</span>
           <span style="flex:1;font-weight:700">${e(r.name || 'Player')}${me ? ' <b style="font-size:.7em;color:var(--color-accent)">YOU</b>' : ''}${i === 0 ? ' <b style="font-size:.7em;color:var(--color-primary)">CHAMPION</b>' : ''}</span>
           <span style="font-weight:900;font-variant-numeric:tabular-nums">${r.score | 0}</span>
         </div>`;
      }).join('') + `</div>`;
  try {
    const base = 'data/leaderboard';
    const index = await fetch(`${base}/index.json`, { cache: 'no-cache' }).then((r) => r.json());
    const seasons = Object.keys(index || {}).sort().reverse();
    if (!seasons.length) { body.innerHTML = emptyLeaderboard(); return; }
    const season = seasons[0];
    const overall = await fetch(`${base}/${season}/_overall.json`).then((r) => r.json()).catch(() => []);
    const sm = seasonMeta();   // L3 seasons: the fresh-start banner
    let html = `<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;padding:12px 14px;border-radius:14px;background:var(--color-primary);color:#fff;margin:6px 0 16px">
       <b>${e(sm.name)}</b><span style="opacity:.9;font-size:.85em">Resets in ${sm.days} day${sm.days === 1 ? '' : 's'} — a fresh climb</span></div>`;
    // L5 social graph: a Friends view — the people you added, ranked by their public standing.
    const myFriends = Identity.friends();
    if (myFriends.length) {
      const scoreByUid = {}; for (const r of overall) scoreByUid[r.uid] = r.score;
      const me = overall.find((r) => r.uid === myUid);
      const fr = [...myFriends.map((f) => ({ uid: f.uid, name: f.name, score: scoreByUid[f.uid] ?? null })),
                  ...(me ? [{ name: `${me.name} (you)`, score: me.score, me: true }] : [])]
        .sort((a, b) => (b.score ?? -1) - (a.score ?? -1));
      html += `<h2 class="section-header">Friends</h2><div style="display:flex;flex-direction:column;gap:6px;margin:8px 0 20px">` + fr.map((f, i) =>
        `<div style="display:flex;align-items:center;gap:10px;padding:10px 14px;border-radius:12px;background:var(--color-surface);${f.me ? 'outline:2px solid var(--color-accent);outline-offset:-2px' : ''}">
           <span style="font-weight:900;width:28px;opacity:.5">${i + 1}</span>
           <span style="flex:1;font-weight:700">${e(f.name)}</span>
           ${f.uid ? `<button data-challenge="${e(f.uid)}" data-cname="${e(f.name)}" style="padding:4px 12px;font-weight:800;border:2px solid var(--color-accent);border-radius:9px;background:transparent;color:var(--color-accent);cursor:pointer;font-size:.85em">Duel</button>` : ''}
           <span style="font-weight:900;font-variant-numeric:tabular-nums">${f.score === null ? '—' : f.score}</span></div>`).join('') + `</div>`;
    }
    html += `<h2 class="section-header">${e(seasonDisplay(season))} · Overall</h2>${table(overall)}`;
    for (const venue of (index[season] || [])) {
      const rows = await fetch(`${base}/${season}/${encodeURIComponent(venue)}.json`).then((r) => r.json()).catch(() => []);
      html += `<h2 class="section-header">${e(venue)}</h2>${table(rows)}`;
    }
    body.innerHTML = html;
    body.querySelectorAll('[data-challenge]').forEach((b) => b.addEventListener('click', () => challengeFriend(b.dataset.challenge, b.dataset.cname)));   // L5 duels
  } catch { body.innerHTML = emptyLeaderboard(); }
}
function emptyLeaderboard() {
  return `<p class="body" style="opacity:.7">No standings yet. Play a live Tidbits night while signed in and you'll climb the board here — it refreshes hourly.</p>`;
}

// L5 async friend duels ---------------------------------------------------
async function buildDuelSet() {
  const topics = ['history', 'science', 'movies', 'music', 'sports', 'geography', 'art', 'nature'];
  const topic = topics[Math.floor(Math.random() * topics.length)];
  const set = await buildCreateSet(topic);
  return set.filter((q) => Array.isArray(q.options) && q.options.length >= 2 && typeof q.correctIndex === 'number').slice(0, 6);
}

async function challengeFriend(uid, name) {
  if (!Identity.signedIn) { toast('Sign in to challenge friends'); return; }
  toast('Building your challenge…');
  const qs = await buildDuelSet();
  if (qs.length < 3) { toast('Couldn’t build a duel set — try again'); return; }
  const id = await Duels.challenge({ uid, name }, qs);
  toast(id ? `Challenge sent to ${name}!` : 'Couldn’t send the challenge');
}

async function playDuel(id) {
  await Duels.accept(id);
  const d = await Duels.load(id);
  if (!d) { toast('Duel not found'); return; }
  location.hash = '#/play';
  startGame('mix', catById('mixed'), { custom: Duels.questionsOf(d), label: 'Duel', duelId: id });
}

function viewDuels() {
  return `<div style="max-width:640px;margin:0 auto;padding:8px 4px">
    <a href="#/records" style="color:var(--color-accent);text-decoration:none;font-weight:700">‹ Records</a>
    <h1 class="view-heading">Duels</h1>
    <p class="body">Challenge a friend to the same questions — whoever scores higher wins. Answer on your own time.</p>
    <div id="duels-body"><p class="body">Loading…</p></div>
  </div>`;
}

async function loadDuels() {
  const body = document.getElementById('duels-body');
  if (!body) return;
  if (!Identity.signedIn) { body.innerHTML = `<p class="body" style="opacity:.7">Sign in to challenge friends and track your duels.</p>`; return; }
  const e = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const [inbox, mine] = await Promise.all([Duels.inbox(), Duels.mine()]);
  const inRow = (v) => `<div class="card pad" style="display:flex;align-items:center;gap:10px;margin-bottom:8px">
      <span style="flex:1"><b>${e(v.fromName || 'A friend')}</b> challenged you</span>
      <button data-duel-play="${e(v.id)}" class="btn btn-primary" style="padding:8px 16px">Play</button></div>`;
  const statusOf = (d) => {
    if (d.myDone && d.oppDone) {
      const res = d.myScore > d.oppScore ? `<b style="color:var(--color-primary)">Won ${d.myScore}–${d.oppScore}</b>` : d.myScore < d.oppScore ? `Lost ${d.myScore}–${d.oppScore}` : `Tied ${d.myScore}–${d.oppScore}`;
      return `${res}${d.oppUid ? ` <button data-rematch="${e(d.oppUid)}" data-rname="${e(d.oppName)}" style="margin-left:8px;padding:4px 12px;font-weight:800;border:2px solid var(--color-accent);border-radius:9px;background:transparent;color:var(--color-accent);cursor:pointer;font-size:.85em">Rematch</button>` : ''}`;
    }
    if (d.myDone) return `<span class="muted">Waiting on ${e(d.oppName)}</span>`;
    return `<button data-duel-play="${e(d.id)}" class="btn btn-primary" style="padding:6px 14px">Your turn</button>`;
  };
  const myRow = (d) => `<div class="card pad" style="display:flex;align-items:center;gap:10px;margin-bottom:8px">
      <span style="flex:1;font-weight:700">vs ${e(d.oppName)}</span>${statusOf(d)}</div>`;
  const mineIds = new Set(mine.map((d) => d.id));
  const pending = inbox.filter((v) => !mineIds.has(v.id));
  body.innerHTML =
    (pending.length ? `<h2 class="section">Challenges for you</h2>${pending.map(inRow).join('')}` : '') +
    (mine.length ? `<h2 class="section">Your duels</h2>${mine.map(myRow).join('')}` : '') +
    (!pending.length && !mine.length ? `<p class="body" style="opacity:.7">No duels yet. Add friends from a live night, then tap Challenge on the Leaderboard.</p>` : '');
  body.querySelectorAll('[data-duel-play]').forEach((b) => b.addEventListener('click', () => playDuel(b.dataset.duelPlay)));
  body.querySelectorAll('[data-rematch]').forEach((b) => b.addEventListener('click', async () => { await challengeFriend(b.dataset.rematch, b.dataset.rname); loadDuels(); }));
}

function viewRecords() {
  const recs = Store.records();
  if (!recs.length) return `<h1 class="page-title">Records</h1>${profileCard()}<div class="empty card pad"><p>No games yet.</p><p class="muted">Play a round and your scores, streaks, and facts to review show up here.</p></div>${settingsSection()}`;
  const lt = Store.lifetime(), st = Store.streak();
  const bests = Object.values(MODES).map((m) => ({ m, best: Store.bestScore(m.id) })).filter((x) => x.best > 0);
  const review = Store.reviewEnabled() ? Store.dueReview(8) : [];
  return `
    <h1 class="page-title">Records</h1>
    ${profileCard()}
    <a href="#/leaderboard" class="card pad" style="display:flex;align-items:center;gap:10px;text-decoration:none;color:inherit;margin-bottom:14px">${ICON.globe}<span style="flex:1;font-weight:700">Leaderboard</span><span class="chev">›</span></a>
    <a href="#/duels" class="card pad" style="display:flex;align-items:center;gap:10px;text-decoration:none;color:inherit;margin-bottom:14px"><span style="flex:1;font-weight:700">Duels</span><span class="chev">›</span></a>
    <div class="banner card daily"><div><div class="muted">DAY STREAK</div><div class="big">${Identity.profile?.streak?.current || 0} days</div></div><div class="muted">best ${Identity.profile?.streak?.longest || 0} 🔥</div></div>
    <div class="stat-row">
      ${statBox(lt.games, 'Games', '#8B5CF6')}${statBox(lt.acc + '%', 'Accuracy', '#2D5BFF')}${statBox(lt.correct, 'Correct', '#2FCB8A')}
    </div>
    <h2 class="section">Your games</h2>
    <p class="muted">Your latest rounds — tap one to see the questions.</p>
    ${recs.slice(0, 3).map((r, i) => gameHistoryRow(r, i)).join('')}
    ${recs.length > 3 ? `<button class="card row rec-tap" data-all-games><span><b>See all ${recs.length} games</b></span><span class="chev">›</span></button>` : ''}
    ${progressSection()}
    ${badgesSection()}
    ${calibrationSection()}
    <h2 class="section">Personal bests</h2>
    <p class="muted">Tap a mode to scroll your previous attempts.</p>
    ${bests.map((x) => `<button class="card row rec-tap" data-best="${x.m.id}"><span><b>${h(x.m.title)}</b><span class="muted"> · ${recs.filter((r) => r.mode === x.m.id).length} played</span></span><span class="big-sm">${x.best} ›</span></button>`).join('') || '<p class="muted">Play a mode to set a best.</p>'}
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
    return `<button class="card topic-row rec-tap" data-domain="${d.id}">
      <span class="topic-ic" style="background:${col}">${c.symbol}</span>
      <div class="topic-main">
        <div class="topic-head"><b>${h(c.name)}</b>${d.hasWedge ? '<span class="wedge">✓</span>' : ''}<span class="lvl" style="background:${col}">Level ${d.level}</span></div>
        <div class="xp-track"><div class="xp-fill" style="width:${Math.max(6, d.levelProgress * 100)}%;background:${col}"></div></div>
        <div class="muted topic-sub">${remaining} more to Level ${d.level + 1}</div>
      </div><span class="chev">›</span></button>`;
  }).join('');
  return `<h2 class="section">Your knowledge</h2>
    <p class="muted">Each domain levels up as you answer its questions correctly. You've explored ${explored} of 8 domains and mastered ${mastered}. A ✓ means mastered — 15+ right at 60%+ accuracy.</p>
    ${rows}`;
}

// L4: levelable badges — recognise real milestones (games, streak, mastery, accuracy, live nights),
// tiered. Plain-language "N more to Tier X" so the number means something; tier number as the icon
// (no emoji chrome, R-ICON-1), reusing the Topic-Level visual language.
function computeBadges() {
  const lt = Store.lifetime();
  const mastered = Store.progress().filter((d) => d.hasWedge).length;
  const longest = Identity.profile?.streak?.longest || 0;
  const liveNights = Identity.profile?.stats?.liveNights || 0;
  const defs = [
    { name: 'Scholar', val: lt.games, tiers: [10, 50, 100, 500], unit: 'games' },
    { name: 'On a Roll', val: longest, tiers: [3, 7, 30, 100], unit: 'day streak' },
    { name: 'Domain Master', val: mastered, tiers: [1, 3, 5, 7], unit: 'domains mastered' },
    { name: 'Sharpshooter', val: lt.games >= 5 ? lt.acc : 0, tiers: [60, 75, 85, 95], unit: '% lifetime accuracy' },
    { name: 'Regular', val: liveNights, tiers: [1, 5, 15, 40], unit: 'live nights' },
  ];
  return defs.map((d) => {
    const tier = d.tiers.filter((t) => d.val >= t).length;
    const next = tier < d.tiers.length ? d.tiers[tier] : null;
    const floor = tier > 0 ? d.tiers[tier - 1] : 0;
    const pct = next === null ? 100 : Math.min(100, Math.max(6, Math.round(((d.val - floor) / (next - floor)) * 100)));
    return { name: d.name, unit: d.unit, val: d.val, tier, max: d.tiers.length, next, pct };
  });
}

function badgesSection() {
  const badges = computeBadges();
  if (!badges.some((b) => b.tier > 0)) return '';   // hide until the player earns their first
  const rows = badges.map((b) => `
    <div class="card topic-row" style="opacity:${b.tier > 0 ? 1 : 0.5}">
      <span class="topic-ic" style="background:${b.tier > 0 ? 'var(--color-primary)' : 'var(--color-border)'};color:#fff">${b.tier || '·'}</span>
      <div class="topic-main">
        <div class="topic-head"><b>${h(b.name)}</b><span class="lvl" style="background:var(--color-accent)">Tier ${b.tier}/${b.max}</span></div>
        <div class="xp-track"><div class="xp-fill" style="width:${b.pct}%;background:var(--color-primary)"></div></div>
        <div class="muted topic-sub">${b.next === null ? `Maxed — ${b.val} ${b.unit}` : `${b.val}/${b.next} ${b.unit} to Tier ${b.tier + 1}`}</div>
      </div></div>`).join('');
  return `<h2 class="section">Badges</h2>
    <p class="muted">Milestones that level up as you play — depth, consistency, and range.</p>
    ${rows}`;
}

// Interactive Records (owner): game history, per-game recap, domain + best
// drill-ins. Answer detail is persisted per game (Store.addRecord answers[]).
function answerDots(rec) {
  const a = rec.answers;
  if (!a || !a.length) {
    let out = '';
    for (let i = 0; i < Math.max(rec.total, 1); i++) out += `<span class="dot" style="background:${i < rec.correct ? 'var(--color-mint)' : 'var(--color-surface)'}"></span>`;
    return `<span class="dots">${out}</span>`;
  }
  return `<span class="dots">${a.slice(0, 24).map((x) => `<span class="dot" style="background:${x.correct ? catColor(catById(x.cat)) : 'var(--color-surface)'}"></span>`).join('')}</span>`;
}
function relTime(at) {
  if (!at) return '';
  const d = Date.now() - at;
  if (d < 60000) return 'just now';
  if (d < 3600000) return Math.floor(d / 60000) + 'm ago';
  if (d < 86400000) return Math.floor(d / 3600000) + 'h ago';
  return Math.floor(d / 86400000) + 'd ago';
}
function gameHistoryRow(rec, i) {
  const m = MODES[rec.mode] || MODES.classic;
  return `<button class="card game-row rec-tap" data-recap="${i}">
    <span class="game-main"><span class="game-head"><b>${h(m.title)}</b><span class="muted"> · ${h((catById(rec.categoryID) || {name:''}).name)}</span></span>
    ${answerDots(rec)}<span class="muted game-sub">${rec.correct}/${rec.total} correct${rec.at ? ' · ' + relTime(rec.at) : ''}</span></span>
    <span class="big-sm">${rec.score}</span></button>`;
}
function answerLine(a) {
  return `<div class="card ans-line"><span class="ans-seal ${a.correct ? 'ok' : 'no'}">${a.correct ? '✓' : '✕'}</span>
    <span><b>${h(a.prompt)}</b><div class="muted">Answer: ${h(a.answer)}</div></span></div>`;
}
function openRecap(rec) {
  const m = MODES[rec.mode] || MODES.classic;
  const acc = rec.total ? Math.round(rec.correct / rec.total * 100) : 0;
  const body = `<h2>${h(m.title)} · ${rec.score}</h2>
    <div class="stat-row">${statBox(rec.correct + '/' + rec.total, 'Correct', '#2FCB8A')}${statBox(acc + '%', 'Accuracy', '#2D5BFF')}</div>
    ${(rec.answers && rec.answers.length) ? rec.answers.map(answerLine).join('') : '<p class="muted">This game was played before per-question history was added, so only the totals are here.</p>'}`;
  showRecordsSheet(body);
}
function openDomain(catId) {
  const recs = Store.records(); const seen = new Set(); const ans = [];
  for (const r of recs) for (const a of (r.answers || [])) if (a.cat === catId && !seen.has(a.qid)) { seen.add(a.qid); ans.push(a); }
  const wrong = ans.filter((a) => !a.correct), right = ans.filter((a) => a.correct);
  const body = `<h2>${h((catById(catId) || {name:''}).name)}</h2>
    ${!ans.length ? '<p class="muted">No per-question history yet for this domain. Play a game here and it’ll show up.</p>' : ''}
    ${wrong.length ? `<h3 class="section">Missed (${wrong.length})</h3>${wrong.map(answerLine).join('')}` : ''}
    ${right.length ? `<h3 class="section">Got right (${right.length})</h3>${right.map(answerLine).join('')}` : ''}`;
  showRecordsSheet(body);
}
// Full game history (WEB-DESIGN §5.3 "See all"): the long tail lives here,
// behind the 3-game summary preview, so Records stays a dashboard not a ledger.
function openAllGames() {
  const recs = Store.records();
  const body = `<h2>All games</h2><p class="muted">Newest first — tap one to see the questions.</p>
    ${recs.map((r, i) => gameHistoryRow(r, i)).join('')}`;
  showRecordsSheet(body);
}
function openBests(modeId) {
  const attempts = Store.records().filter((r) => r.mode === modeId);
  const best = attempts.reduce((m, r) => Math.max(m, r.score), 0);
  const m = MODES[modeId] || MODES.classic;
  const body = `<h2>${h(m.title)} attempts</h2><p class="muted">Newest first. Your best is ${best}.</p>
    ${attempts.map((r) => Store.records().indexOf(r)).map((idx) => { const r = Store.records()[idx]; return `<button class="card game-row rec-tap" data-recap="${idx}">
      <span class="game-main"><span class="game-head">${r.score === best ? '🏆 ' : ''}<b>${r.at ? relTime(r.at) : r.date}</b></span>${answerDots(r)}</span><span class="big-sm">${r.score} ›</span></button>`; }).join('')}`;
  showRecordsSheet(body);
}
function showRecordsSheet(bodyHTML) {
  let dlg = document.getElementById('rec-dlg');
  if (!dlg) { dlg = document.createElement('dialog'); dlg.id = 'rec-dlg'; dlg.className = 'night-dlg'; document.body.appendChild(dlg); }
  dlg.innerHTML = `<div class="night-form rec-sheet">${bodyHTML}<div class="night-actions"><button type="button" class="btn" data-rec-close>Done</button></div></div>`;
  dlg.querySelector('[data-rec-close]').addEventListener('click', () => dlg.close());
  dlg.querySelectorAll('[data-recap]').forEach((b) => b.addEventListener('click', () => { dlg.close(); openRecap(Store.records()[+b.dataset.recap]); }));
  dlg.showModal();
}
function bindRecords() {
  app.querySelectorAll('[data-recap]').forEach((b) => b.addEventListener('click', () => openRecap(Store.records()[+b.dataset.recap])));
  app.querySelectorAll('[data-domain]').forEach((b) => b.addEventListener('click', () => openDomain(b.dataset.domain)));
  app.querySelectorAll('[data-best]').forEach((b) => b.addEventListener('click', () => openBests(b.dataset.best)));
  app.querySelector('[data-all-games]')?.addEventListener('click', openAllGames);
  const rt = $('#review-toggle'); if (rt) rt.addEventListener('change', (e) => Store.setReviewEnabled(e.target.checked));
  const pt = $('#reminder-toggle');
  if (pt) {
    // The switch reflects the REAL subscription, which is async, so it starts off and
    // corrects itself — never the other way round, or an off state reads as a broken opt-out.
    Push.isSubscribed().then((sub) => { pt.checked = sub; });
    pt.addEventListener('change', async (e) => {
      if (e.target.checked) { const ok = await Push.enable(); e.target.checked = ok; }
      else await Push.disable();
    });
  }
}

// ---------------- Game engine ----------------
class Game {
  constructor(mode, category, opts = {}) {
    this.mode = MODES[mode]; this.category = category; this.label = opts.label;
    this.dailyDay = opts.dailyDay || null;   // archive plays of a past Daily (R-DAILY-1)
    // Play vs CPU (Decision 038): a bot resolving the same questions.
    this.versus = opts.versusBot ? new VsMatch([botById(opts.versusBot, recentAccuracy())]) : null;
    this.mixModes = opts.mixModes || null;   // Custom Mix: multi-select Customize
    this._online = opts.online || null;      // Online Quick Match coordinator (Decision 040)
    this.questions = []; this.index = 0; this.score = 0; this.streak = 0; this.maxStreak = 0;
    this.answered = []; this.chosen = null; this.phase = 'loading';
    this.remaining = 0; this.timer = null; this.qStart = 0; this.globalDeadline = null;
    this._custom = opts.custom;
    // Weak-Spot Arena (Club): per-question "why you're seeing this" reason, keyed
    // by question ID, + how many of this round's questions were TRUE misses (vs.
    // category-fill) — the "gaps closed" tally reads off both.
    this._weakSpotReasons = opts.weakSpotReasons || null;
    this._weakSpotMissCount = opts.weakSpotMissCount ?? null;
    // Marathon (Club): the in-progress run this session is playing into, + how
    // many questions were already answered in EARLIER sessions (so the HUD shows
    // the true 84/200 position, not this session's local index). The finished
    // MarathonScore lands in `_marathonScore` for renderMarathonResults.
    this._marathonRun = opts.marathonRun || null;
    this._marathonOffset = opts.marathonOffset || 0;
    this._marathonScore = null;
    // Expedition stage play only (Club feature 5): which campaign + stage this
    // round belongs to (null for every other launch). It IS a normal round —
    // _persist() still writes a GameRecord — but _end() ALSO records the
    // campaign-specific pass/fail outcome, landing here for
    // renderExpeditionStageResult.
    this._expeditionId = opts.expeditionId ?? null;
    this._expeditionStageIndex = opts.expeditionStageIndex ?? null;
    this._expeditionOutcome = null;
    this._duelId = opts.duelId;   // L5: submit this game's score to the duel on finish
    // Trivia Night: the plan's rounds [[kind, count], …] + the per-round meta for banners.
    this._nightPlan = opts.nightPlan || (mode === 'barTrivia' ? { rounds: NIGHT.presets[1].rounds } : null);
    this._nightRounds = (this._nightPlan?.rounds || []).map(([kind]) => ({ kind, title: NIGHT.roundTitle[kind] || kind }));
    // Stake: the remaining confidence-chip budget + the chip on this question (0 = unset).
    this.stakeTiers = this.mode.id === 'stake' ? STAKE_BUDGET.map((t) => ({ value: t.value, label: t.label, remaining: t.count })) : [];
    this.currentStake = 0;
    this.stakeOutcomes = {}; // F1 calibration: tierValue -> {hits, total}
  }
  // Never-empty pull for a category-filtered special type: try the picked
  // category, then relax to the whole type pool ('mixed') to top up. Keeps the
  // MODE pure (a Match Up round stays Match Up) while covering corpus holes like
  // sports×matching. (oddOneOut/enumerate already pull 'mixed' directly.)
  _pullType(set, count, seen = Store._seen) {
    let qs = set.pull(this.category.id, seen, count);
    if (qs.length < count && this.category.id !== 'mixed') {
      const have = new Set([...seen, ...qs.map((q) => q.id)]);
      qs = qs.concat(set.pull('mixed', have, count - qs.length));
    }
    return qs;
  }
  async load() {
    let qs;
    if (this._custom) qs = this._custom;
    else if (this.mode.id === 'barTrivia') qs = await this._loadNight();
    else if (this.mode.id === 'daily') {
      // The Daily ranks EVERY id, so a shard would produce a different seven than the
      // other platforms — which is why this was the one play path that paid 13 MB for the
      // full corpus. The cron publishes the day's seven as ~4 KB of static JSON; take that
      // when it's there, and fall back to computing locally whenever it isn't.
      const day = this.dailyDay || dayKey();
      qs = await Corpus.dailyPublished(day, 7);
      if (!qs) {
        await Corpus.loadFull();
        qs = Corpus.daily(day, 7);
      }
    }
    else if (this.mode.id === 'mix') qs = this._loadMix();
    else if (this.mode.id === 'pictureId') {
      await Pictures.load();
      qs = this._pullType(Pictures, this.mode.count);
    }
    else if (this.mode.id === 'thisOrThat') {
      await ThisOrThat.load();
      qs = this._pullType(ThisOrThat, this.mode.count);
    }
    else if (this.mode.id === 'closestCall') {
      await ClosestCall.load();
      qs = this._pullType(ClosestCall, this.mode.count);
    }
    else if (this.mode.id === 'ordering') {
      await Ordering.load();
      qs = this._pullType(Ordering, this.mode.count);
    }
    else if (this.mode.id === 'matching') {
      await Matching.load();
      qs = this._pullType(Matching, this.mode.count);
    }
    else if (this.mode.id === 'typeAnswer') {
      await TypeAnswer.load();
      qs = this._pullType(TypeAnswer, this.mode.count);
    }
    else if (this.mode.id === 'oddOneOut') {
      // Now that every category has odd-one-out coverage, honor the picked
      // category (with the mixed fallback for safety).
      await OddOneOut.load();
      qs = this._pullType(OddOneOut, this.mode.count);
    }
    else if (this.mode.id === 'enumerate') {
      // Enumeration is a REPLAYABLE recall drill — naming the countries of Asia
      // again is the point — so ignore the seen-set (pass an empty one).
      await Enumerate.load();
      qs = this._pullType(Enumerate, this.mode.count, new Set());
    }
    else if (this.mode.id === 'ladder') {
      await Difficulty.load();
      // The pool must come from the PICKED category: this asked for 'mixed'
      // regardless, so a Ladder run in Geography delivered whatever share of the
      // mixed corpus happens to be geography — measured, 13%.
      const pool = Corpus.pull(this.category.id, Store._seen, 80).sort((a, b) => Difficulty.get(a.sourceTitle) - Difficulty.get(b.sourceTitle));
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
    // Last-resort backstop: if a type file failed to load entirely, never strand
    // the player on an error — give them a Classic round from the always-present
    // 20k corpus. Only a total corpus-load failure (offline, no cache) errors.
    if (!this.questions.length && this.mode.id !== 'daily') {
      const classic = Corpus.pull(this.category.id, Store._seen, this.mode.count);
      this.questions = classic.slice(0, this.mode.count);
      Store.markSeen(this.questions.map((q) => q.id));
    }
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
  startRound() {
    if (this.phase !== 'roundIntro') return;
    this._introducedRound = this.current?.roundIndex ?? null;
    this._begin();   // handles clock + render itself
  }

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
  // Custom Mix: pull from EVERY selected mode, shuffle together (no rounds).
  async _loadMix() {
    const modes = this.mixModes && this.mixModes.length ? this.mixModes : ['classic'];
    const per = Math.max(2, Math.ceil(this.mode.count / modes.length) + 1);
    const seen = new Set(Store._seen);
    const pool = [];
    for (const m of modes) {
      const qs = await this._sourceType(m, per, seen);
      for (const q of qs) { q.roundIndex = null; pool.push(q); seen.add(q.id); }
    }
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]];
    }
    return pool.slice(0, this.mode.count);
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
    const cur = this.current;
    // A night HOLDS on a round interstitial when a new round begins
    // (owner: rounds must be FELT, not just a banner swap).
    if (this.mode.id === 'barTrivia' && cur && cur.roundIndex != null && cur.roundIndex !== this._introducedRound) {
      this.phase = 'roundIntro'; clearInterval(this.timer); renderGame(); return;
    }
    this.chosen = null; this.currentStake = 0; this.phase = 'playing'; this.qStart = Date.now();
    if (this.versus && cur) this.versus.beginQuestion(cur, this.mode.perQuestion ?? 30);
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
      ?? (this.mode.id === 'barTrivia' || this.mode.id === 'mix' ? NIGHT.shapeBudget(cur) : this.mode.perQuestion)
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
    // Partial credit measured ABOVE CHANCE.
    // The old rule paid 40 * (1 - inversions/maxInversions), which starts a shuffled board at half marks: measured by playing every mode to lose, a player who never touched the board scored 93-154 of a possible 240.
    // The random baseline is now the zero.
    // Still adds-only (Decision 022).
    const share = maxInv === 0 ? 0 : 1 - inv / maxInv;
    const pts = maxInv === 0 ? 0 : Math.round(40 * Math.max(0, (share - 0.5) / 0.5));
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
    // Marathon (Club): persist THIS answer immediately, not batched — a
    // tab-close/crash mid-run never loses progress (the whole point of Marathon).
    if (this.mode.id === 'marathon' && this._marathonRun) {
      Marathon.record(this._marathonRun, { qid: q.id, categoryId: q.categoryID, difficulty: q.difficulty, correct });
    }
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
  _end() {
    clearInterval(this.timer); this.phase = 'finished';
    // Marathon writes NO GameRecord/MissedFact/SeenStory — a single session's
    // slice of a multi-session run would misreport lifetime stats (deliberate,
    // mirrors the Apple reference). It writes its own permanent MarathonScore
    // instead, exactly when the run reaches its true end.
    if (this.mode.id === 'marathon' && this._marathonRun) {
      this._marathonScore = Marathon.finish(this._marathonRun);
      this._marathonRun = null;
    } else {
      this._persist();
      // Expedition (Club feature 5): a stage IS a normal round (the GameRecord
      // was just written above) — this ADDS the campaign-specific pass/fail
      // outcome (pass advances/unlocks; the last stage passing writes a
      // permanent certificate).
      if (this._expeditionId != null && this._expeditionStageIndex != null) {
        const s = this.summary();
        this._expeditionOutcome = Expeditions.recordStageResult(this._expeditionId, this._expeditionStageIndex, s.correct, s.total);
      }
    }
    if (this._online) { this._online.reportProgress(this.score, true); this._online.renderStandings(); return; }
    this._resultsShown = true;   // F-013: from here the URL may reclaim the screen
    renderResults();
  }
  _persist() {
    const correct = this.answered.filter((a) => a.correct).length;
    if (this.mode.id === 'daily') { const dk = this.dailyDay || dayKey(); Store.recordDaily(dk, this.score); Identity.syncDailyScore(dk, this.score); }
    // Only TODAY'S daily feeds the streak — archive catch-ups don't (R-DAILY-1).
    const answers = this.answered.map((a) => ({ qid: a.q.id, prompt: a.q.prompt, cat: a.q.categoryID, correct: !!a.correct, answer: a.q.options[a.q.correctIndex] || (a.q.closest ? closestFmtVal(a.q.closest.answer, a.q.closest) : '') }));
    Store.addRecord({ mode: this.mode.id, categoryID: this.category.id, score: this.score, correct, total: this.answered.length, maxStreak: this.maxStreak, date: dayKey(), at: Date.now(), answers },
      (this.dailyDay || dayKey()) === dayKey());
    Store.recordMisses(this.answered);
    Store.recordTelemetry(this.mode.id, this.answered);
    Store.recordSeen(this.answered);   // Story Archive (Club feature 2) — every answered question, right or wrong
    Identity.recordGame(correct, this.answered.length);   // feed the portable identity
    if (this.mode.id === 'stake') Store.addCalibration(this.stakeOutcomes);
  }
  summary() {
    const correct = this.answered.filter((a) => a.correct).length;
    return { correct, total: this.answered.length, score: this.score, maxStreak: this.maxStreak, answered: this.answered, acc: this.answered.length ? Math.round(correct / this.answered.length * 100) : 0 };
  }
  // Weak-Spot Arena's payoff — count of TRUE-miss questions (not category-fill)
  // answered correctly this round. null outside .weakSpot.
  weakSpotGapsClosed() {
    if (this.mode.id !== 'weakSpot' || !this._weakSpotReasons) return null;
    const trueMissIDs = new Set(Object.keys(this._weakSpotReasons).filter((id) => this._weakSpotReasons[id].startsWith('Missed')));
    return this.answered.filter((a) => a.correct && trueMissIDs.has(a.q.id)).length;
  }
}

async function startGame(mode, category, opts) {
  game = new Game(mode, category, opts);
  renderLoading('Pulling fresh tidbits…');
  await game.load();
  if (game.phase === 'error') renderGameError();
}

function quitGame() { if (game && game._online) { OnlineMatch.leave(); return; } if (game) clearInterval(game.timer); game = null; render(); }

// ---------------- Game render ----------------
// The beat between rounds of a Trivia Night — what's coming and how many
// questions, then an explicit start (owner: rounds must be FELT).
function renderRoundIntro() {
  const ri = game.current?.roundIndex ?? 0;
  const [kind, count] = (game._nightPlan?.rounds || [])[ri] || ['classic', 0];
  const title = NIGHT.roundTitle[kind] || kind;
  app.innerHTML = `
    <div class="round-intro">
      <div class="muted round-intro-kicker">ROUND ${ri + 1} OF ${(game._nightPlan?.rounds || []).length}</div>
      <h1 class="page-title">${h(title)}</h1>
      <p class="muted">${count} questions</p>
      <button class="btn btn-primary btn-full" data-start-round>Start Round ${ri + 1}</button>
      <button class="btn btn-text btn-full" data-quit>Quit the night</button>
    </div>`;
  $('[data-start-round]').addEventListener('click', () => game.startRound());
  $('[data-quit]').addEventListener('click', quitGame);
}

// Live online standings during a match (Decision 040): you vs each opponent.
function onlineStrip() {
  const roster = game._online._roster();
  const cells = roster.map((r) => `<span>${h((r.name || 'Player').split(' ')[0])}${r.me ? ' (you)' : ''} ${r.score || 0}</span>`).join('');
  return `<div class="vs-strip">${cells}</div>`;
}

// "You 320 · Ace Botsworth CPU 410" — the running head-to-head (Decision 038).
function versusStrip() {
  const seats = game.versus.seats.map((s) =>
    `<span>${h(s.bot.name)} ${s.score} <span class="cpu-tag">CPU</span></span>`).join('');
  return `<div class="vs-strip"><span>You ${game.score}</span>${seats}</div>`;
}

// What the opponent did on THIS question — inside the reveal beat.
function versusRevealCard() {
  const rows = game.versus.seats.map((s) => {
    const a = game.versus.pending.find((x) => x.botId === s.bot.id);
    let line;
    if (!a || a.choiceIndex == null) line = `${h(s.bot.name)} ran out of time`;
    else if (s.lastCorrect) line = `${h(s.bot.name)} got it in ${a.seconds.toFixed(1)}s`;
    else line = `${h(s.bot.name)} missed it`;
    return `<div class="vs-line ${s.lastCorrect ? 'hit' : 'miss'}">${line}</div>`;
  }).join('');
  return `<div class="card reveal vs-reveal">${rows}</div>`;
}

function renderGame() {
  const q = game.current; if (!q) return;
  if (game.phase === 'roundIntro') { renderRoundIntro(); return; }
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
  // Weak-Spot Arena's "why you're seeing this" — transparency by construction,
  // never an opaque model (docs/CLUB-FEATURES-BUILD.md "Feature 1").
  const weakReason = game.mode.id === 'weakSpot' && game._weakSpotReasons ? game._weakSpotReasons[q.id] : null;
  // Expedition (Club feature 5): a small in-play indicator of which campaign +
  // stage this round belongs to (mirrors the Weak-Spot reason caption).
  const expeditionLine = (game._expeditionId != null)
    ? `${Expeditions.named(game._expeditionId)?.title || ''} · Stage ${game._expeditionStageIndex + 1}` : null;
  if (game.versus && game.phase === 'reveal') game.versus.commit(q, game.index, game.mode.perQuestion ?? 30);
  if (game._online && game.phase === 'reveal') game._online.reportProgress(game.score, false);
  const reveal = game.phase === 'reveal' ? revealCard(q) + (game.versus ? versusRevealCard() : '') : '';
  const banner = (game.mode.id === 'barTrivia' && game.currentRound) ? nightBanner() : '';
  const fixedCount = game.mode.id !== 'timeAttack' && game.mode.id !== 'survival';
  // Marathon's HUD adds the offset (questions answered in EARLIER sessions)
  // back in so the player always sees their true position out of 200, not this
  // session's local (resumed-slice) index.
  const progress = game.mode.id === 'marathon' ? `${game._marathonOffset + game.index + 1} / ${game._marathonOffset + game.questions.length}`
    : fixedCount ? `${game.index + 1} / ${game.questions.length}` : `#${game.index + 1}`;
  app.innerHTML = `
    <div class="game">
      <div class="hud">
        <button class="x" data-quit>✕</button>
        <span class="pill streak ${game.streak >= 2 ? 'hot' : ''}">${ICON.flame} ${game.streak}</span>
        <span class="pill score">★ ${game.score}</span>
      </div>
      <div class="clockbar"><span id="clk-label">${progress}</span><div class="clock-track"><div id="clk-fill" class="clock-fill"></div></div><span id="clk-secs"></span></div>
      ${game.versus ? versusStrip() : ''}
      ${game._online ? onlineStrip() : ''}
      <div class="qwrap">
        ${banner}
        ${pic}
        <div class="card qcard"><div class="qcat" style="color:${catColor(cat)}">${h(cat.name.toUpperCase())}</div><div class="qprompt">${h(q.prompt)}</div></div>
        ${weakReason ? `<div class="weakspot-reason">${h(weakReason)}</div>` : ''}
        ${expeditionLine ? `<div class="expedition-instage">${h(expeditionLine)}</div>` : ''}
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
// Final standings for a vs-CPU match (Decision 038) — winner banner + rows.
function renderVersusResults(s) {
  const top = game.versus.standings[0];
  const won = game.score >= (top ? top.score : 0);
  const row = (name, score, isCpu, highlight) =>
    `<div class="card vs-standing ${highlight ? 'win' : ''}"><b>${h(name)}${isCpu ? ' <span class="cpu-tag">CPU</span>' : ''}</b><span class="vs-score">${score}</span></div>`;
  app.innerHTML = `
    <div class="results">
      <h1 class="page-title">${won ? 'You won! 🎉' : h(top.bot.name) + ' takes it'}</h1>
      ${row('You', game.score, false, won)}
      ${game.versus.standings.map((t) => row(t.bot.name, t.score, true, !won && t === top)).join('')}
      <p class="muted">${s.correct}/${s.total} correct · rematches sharpen recall</p>
      <button class="btn btn-primary btn-full" data-again>Rematch</button>
      <button class="btn btn-text btn-full" data-done>Done</button>
    </div>`;
  $('[data-again]').addEventListener('click', () => startGame('classic', catById('mixed'), { versusBot: game.versus.seats[0].bot.id }));
  $('[data-done]').addEventListener('click', quitGame);
}

// L2: the cross-context day streak made visible — encouragement, never punishing (no
// countdown timers or "your streak dies!" anxiety; freezes are shown as reassurance).
function streakMoment() {
  const st = Identity.profile?.streak;
  if (!st || st.current < 1) return '';
  const best = st.current > 1 && st.current === st.longest ? ' · your best ever!' : '';
  const freezeLine = st.freezes > 0
    ? `<div class="muted" style="font-size:.85rem">🧊 ${st.freezes} freeze${st.freezes === 1 ? '' : 's'} banked — miss a day and this keeps your streak alive</div>`
    : '';
  return `<div class="card pad" style="text-align:center"><div class="huge" style="color:#FF7A00">🔥 ${st.current}</div><div class="muted"><b>day streak</b>${best}</div>${freezeLine}</div>`;
}

function renderResults() {
  // Marathon reads the permanent MarathonScore just written (a run's true
  // total spans however many sessions it took to finish, not just this one).
  if (game.mode.id === 'marathon') { renderMarathonResults(game._marathonScore); return; }
  // Expedition (Club feature 5): the campaign-specific pass/fail beat, not the
  // generic results screen.
  if (game._expeditionId != null) { renderExpeditionStageResult(); return; }
  const s = game.summary();
  const grid = s.answered.map((a) => (a.chosen === null ? '⚫️' : a.correct ? '🟢' : '🔴')).join('');
  if (game.versus) { renderVersusResults(s); return; }
  const headline = s.acc === 100 ? 'Flawless!' : s.acc >= 80 ? 'Brilliant' : s.acc >= 50 ? 'Nicely done' : 'Good run';
  const missed = s.answered.filter((a) => !a.correct);
  const nailed = s.answered.filter((a) => a.correct && (a.q.difficulty || 3) >= 4);   // L5: hard-correct → "how did you know that?"
  const gapsClosed = game.weakSpotGapsClosed();   // Weak-Spot Arena's payoff (Club feature 1); null elsewhere
  app.innerHTML = `
    <div class="results">
      <div class="card scorecard" style="--tint:${catColor(game.category)}">
        <div class="muted">${h(headline.toUpperCase())}</div><div class="huge">${s.score}</div>
        <div class="muted">${h(game.label || game.mode.title)} · ${h(game.category.name)}</div></div>
      ${gapsClosed != null ? `<div class="card pad weakspot-gaps"><div class="gaps-headline">You closed ${gapsClosed} gap${gapsClosed === 1 ? '' : 's'}</div><div class="muted">${gapsClosed > 0 ? 'Turned a miss into a win' : 'Nothing to close yet this round'}</div></div>` : ''}
      <div class="stat-row">${statBox(s.correct + '/' + s.total, 'Correct', '#2FCB8A')}${statBox(s.acc + '%', 'Accuracy', '#2D5BFF')}${statBox(s.maxStreak, 'Best streak', '#FF5C5C')}</div>
      <div class="card pad grid-card"><div class="emoji">${grid}</div><div class="muted">Spoiler-free — safe to share</div></div>
      ${streakMoment()}
      ${missed.length ? `<h2 class="section">Tidbits to remember</h2>${missed.map((a) => `<div class="card pad"><b>${h(a.q.prompt)}</b><div class="ans">Answer: ${h(a.q.options[a.q.correctIndex])}</div><p class="muted">${h(a.q.explanation)}</p></div>`).join('')}` : ''}
      ${nailed.length ? `<h2 class="section">Tough ones you nailed</h2>${nailed.map((a, i) => `<div class="card pad"><b>${h(a.q.prompt)}</b><div class="ans">You got it: ${h(a.q.options[a.q.correctIndex] || '')}</div><button class="btn btn-text" data-hdyk="${i}" style="padding:6px 0;color:var(--color-accent);text-align:left">How did you know that? · Share ›</button></div>`).join('')}` : ''}
      <button class="btn btn-blue btn-full" data-share>Share Score</button>
      ${game._custom && !game.quizID ? '<button class="btn btn-full" data-save-set>Save this quiz</button>' : ''}
      ${game.mode.id === 'daily' ? '' : '<button class="btn btn-primary btn-full" data-again>Play Again</button>'}
      <button class="btn btn-text btn-full" data-done>Done</button>
    </div>`;
  $('[data-share]').addEventListener('click', () => shareResult(s, grid));
  const saveBtn = $('[data-save-set]');
  if (saveBtn) saveBtn.addEventListener('click', () => {
    // Goes through the contract store, not the retired tidbits.savedSets key —
    // writing there would resurrect the legacy format the migration just cleared.
    saveCreated({ questions: game._custom, topic: (game.label || 'My quiz').trim(),
                  creatorID: 'local', creatorName: '' });
    saveBtn.textContent = 'Saved ✓'; saveBtn.disabled = true;
  });
  const again = $('[data-again]');
  if (again) again.addEventListener('click', () => {
    // Rebuild fresh (misses just changed) rather than replay the exact same set.
    if (game.mode.id === 'weakSpot') { openWeakSpot(); return; }
    startGame(game.mode.id, game.category, game._custom ? { custom: game._custom, label: game.label } : undefined);
  });
  $('[data-done]').addEventListener('click', quitGame);
  app.querySelectorAll('[data-hdyk]').forEach((b) => b.addEventListener('click', () => shareHDYK(nailed[+b.dataset.hdyk])));
  if (game.mode.id === 'daily' && !game.dailyDay) submitDailyBoardResult(s);   // today's Daily → the global board (archive replays don't count)
  // Push (docs/PUSH-CONTRACT.md): ask for notifications WITH CONTEXT, right after a Daily,
  // where "your Daily is ready" means something — never on load. Asked at most once
  // unprompted; the Settings toggle is the way back in after that.
  if (game.mode.id === 'daily' && !Push.hasAsked) Push.enable();
  else Push.refresh();
  if (game._duelId) {   // L5: submit my score to the duel + show the outcome
    const duelId = game._duelId, myScore = s.score;
    Duels.submit(duelId, myScore).then(async () => {
      const d = await Duels.load(duelId), me = Identity.authUid;
      const oppUid = Object.keys(d?.players || {}).find((u) => u !== me);
      const opp = oppUid ? d.players[oppUid] : null;
      const line = !opp?.done ? `Your ${myScore} is in — waiting on ${opp?.name || 'your friend'} to play.`
        : myScore > opp.score ? `You won the duel ${myScore}–${opp.score}!`
        : myScore < opp.score ? `${opp.name} took this one ${opp.score}–${myScore}. Rematch?`
        : `Dead tie, ${myScore}–${opp.score}.`;
      const results = document.querySelector('.results');
      if (results) {
        const card = document.createElement('div');
        card.className = 'card pad'; card.style.marginTop = '12px';
        card.innerHTML = `<b>Duel result</b><div class="muted" style="margin:4px 0 8px">${line}</div><a href="#/duels" style="color:var(--color-accent);font-weight:700">See all duels ›</a>`;
        results.insertBefore(card, results.children[1] || null);
      }
    });
  }
}
// The Daily's global board (docs/DAILY-BOARD-CONTRACT.md): write the one per-day result,
// then invite the player to see where they landed against the world. `marks` is aligned
// to the SHARED pickDaily order (by qid), not the play order, so per-question accuracy is
// comparable across every player. This layers on the Daily — it never replaces the streak.
async function submitDailyBoardResult(s) {
  const day = dayKey();
  await Corpus.loadFull();
  const qids = Corpus.daily(day, 7).map((q) => q.id);
  const byId = new Map(s.answered.map((a) => [a.q.id, a]));
  const marks = qids.map((id) => (byId.get(id)?.correct ? '1' : '0')).join('');
  const correct = s.answered.filter((a) => a.correct).length;
  const ms = Math.round(s.answered.reduce((t, a) => t + (a.taken || 0), 0) * 1000);
  const p = Identity.profile || {};
  const row = { name: p.name || 'Player', avatarSeed: p.avatarSeed || '', score: s.score, correct, marks, ms, at: Date.now() };
  localStorage.setItem('tidbits.dailyboard.score', String(s.score));
  localStorage.setItem('tidbits.dailyboard.marks', marks);
  try { await FirebaseNet.submitDailyBoard(day, row); } catch { /* offline: the board loads on reconnect */ }
  const results = document.querySelector('.results');
  if (results) {
    const card = document.createElement('div');
    card.className = 'card pad'; card.style.marginTop = '12px';
    card.innerHTML = `<b>The whole world played today’s set</b>
      <div class="muted" style="margin:4px 0 8px">Your ${s.score} is in. See where you landed against everyone today.</div>
      <button class="btn btn-blue" data-db-board>See the global board ›</button>`;
    results.insertBefore(card, results.children[1] || null);
    // A finished game still owns render(); clear it so the board route can take over.
    card.querySelector('[data-db-board]').addEventListener('click', () => { game = null; renderDailyBoard(); });
  }
}

// ---------------- Link Wall (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md
// "Feature 6") ----------------
// A NYT-Connections-style SECOND daily: 16 tiles hide 4 themed groups of 4. Unlike
// the game engine's MCQ modes, Link Wall never routes through startGame/GameEngine
// — it owns its own tiny play loop here (mirrors the iOS LinkWallView, which for
// the same reason never routes through GameContainerView/GameEngine either). `lw`
// is the one in-memory session (mirrors the module-level `game` variable).
let lw = null;   // { day, puzzle, result, remaining, selected, solved, oneAway, shaking }
let lwOneAwayToken = 0;
let lwShakeToken = 0;

function linkWallLoadingHTML() {
  return `${linkWallBackHTML()}<h1 class="page-title">Link Wall</h1>
    <div class="center-screen"><div class="spinner"></div></div>`;
}
function linkWallBackHTML() {
  return `<button data-back style="background:none;border:none;font-weight:800;color:var(--color-accent);cursor:pointer;padding:8px 0;font-size:1rem">‹ Back</button>`;
}

// Entry point for the #/linkwall route — async because building today's board
// needs match.json loaded (same lazy load the Matching mode already does).
async function loadLinkWallRoute() {
  if (!Entitlement.isClub) { linkWallReplaceMain(linkWallPaywallHTML()); bindLinkWallBackOnly(); return; }
  try { await Matching.load(); } catch { /* handled by the empty-pool check below */ }
  const day = dayKey();
  const puzzle = LinkWall.puzzle(day, Matching.questions);
  if (!puzzle) { linkWallReplaceMain(linkWallUnavailableHTML()); bindLinkWallBackOnly(); return; }
  lw = initLinkWallState(day, puzzle);
  renderLinkWallBoard();
}

function linkWallReplaceMain(html) {
  const main = $('.main');
  if (main) main.innerHTML = html;
}
function bindLinkWallBackOnly() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { location.hash = '#/play'; });
}

// Non-member paywall (rule 6: never a blank wall) — a real, concrete illustration
// (Marathon-style; Link Wall has no free-tier player data to sample from either).
function linkWallPaywallHTML() {
  return `${linkWallBackHTML()}<h1 class="page-title">Link Wall</h1>
    <div class="card pad" style="margin-bottom:14px"><p class="body-strong">${h(LinkWall.previewLine())}</p></div>
    <div class="card pad" style="text-align:center">
      <p class="body-strong">16 tiles. 4 hidden groups. 4 mistakes allowed.</p>
      <p class="muted">A second daily, NYT-Connections style — find all four groups before you run out of guesses.</p>
      <a href="#/club" class="btn btn-primary" style="margin-top:12px;display:inline-block;text-decoration:none">Join Tidbits Club</a>
    </div>`;
}
function linkWallUnavailableHTML() {
  return `${linkWallBackHTML()}<h1 class="page-title">Link Wall</h1>
    <div class="empty card pad"><p>Couldn't build today's board from the corpus. Try again tomorrow.</p></div>`;
}

// Every tile's true group — the answer key behind "one away", collapse-on-correct,
// and the share grid's colors (mirrors LinkWallView.tileGroup).
function lwTileGroupMap(puzzle) {
  const map = {};
  puzzle.groups.forEach((g) => g.members.forEach((m) => { map[m] = g; }));
  return map;
}

// Resumes a mid-progress OR completed day from the persisted row rather than
// always starting a fresh board (mirrors LinkWallView.loadIfNeeded).
function initLinkWallState(day, puzzle) {
  const result = LinkWallLog.resultOrCreate(day);
  const byLabel = {};
  puzzle.groups.forEach((g) => { byLabel[g.label] = g; });
  const solved = (result.solvedLabels || []).map((l) => byLabel[l]).filter(Boolean);
  const solvedMembers = new Set(solved.flatMap((g) => g.members));
  const remaining = puzzle.tiles.filter((t) => !solvedMembers.has(t));
  return { day, puzzle, result, remaining, selected: [], solved, oneAway: null, shaking: false };
}

function renderLinkWallBoard() {
  if (!lw) return;
  linkWallReplaceMain(lw.result.completed ? linkWallResultHTML() : linkWallBoardHTML());
  bindLinkWallInteractions();
}

function linkWallBoardHTML() {
  const mistakesDots = Array.from({ length: 4 }, (_, i) =>
    `<span class="dot${i < (4 - lw.result.mistakes) ? ' on' : ''}"></span>`).join('');
  const solvedRows = lw.solved.map(linkWallGroupRowHTML).join('');
  const tilesHTML = lw.remaining.map((t) => `<button type="button" class="linkwall-tile${lw.selected.includes(t) ? ' sel' : ''}" data-lw-tile="${h(t)}">${h(t)}</button>`).join('');
  const oneAway = lw.oneAway ? `<div class="linkwall-oneaway">${h(lw.oneAway)}</div>` : '';
  return `${linkWallBackHTML()}<h1 class="page-title">Link Wall</h1>
    <p class="muted">Find the four groups of four.</p>
    <div class="linkwall-mistakes"><span class="lw-mistakes-label">MISTAKES</span><span class="dots">${mistakesDots}</span></div>
    ${solvedRows}
    <div class="linkwall-grid${lw.shaking ? ' shake' : ''}">${tilesHTML}</div>
    ${oneAway}
    <div class="linkwall-actions">
      <button type="button" class="btn btn-quiet" data-lw-deselect ${lw.selected.length ? '' : 'disabled'}>Deselect All</button>
      <button type="button" class="btn btn-quiet" data-lw-shuffle>Shuffle</button>
      <button type="button" class="btn btn-primary" data-lw-submit ${lw.selected.length === 4 ? '' : 'disabled'}>Submit</button>
    </div>`;
}

function linkWallGroupRowHTML(g) {
  return `<div class="linkwall-group-row lw-diff-${g.difficulty}">
    <div class="linkwall-group-label">${h(g.label)}</div>
    <div class="linkwall-group-members">${g.members.map(h).join(' · ')}</div>
  </div>`;
}

function bindLinkWallInteractions() {
  app.querySelector('[data-back]')?.addEventListener('click', () => { location.hash = '#/play'; });
  if (!lw || lw.result.completed) { bindLinkWallResultInteractions(); return; }
  app.querySelectorAll('[data-lw-tile]').forEach((b) => b.addEventListener('click', () => {
    lwToggleTile(b.dataset.lwTile); renderLinkWallBoard();
  }));
  $('[data-lw-deselect]')?.addEventListener('click', () => { lw.selected = []; renderLinkWallBoard(); });
  $('[data-lw-shuffle]')?.addEventListener('click', () => { lw.remaining = shuffleInPlace(lw.remaining); renderLinkWallBoard(); });
  $('[data-lw-submit]')?.addEventListener('click', () => { lwSubmit(); renderLinkWallBoard(); });
}

// Plain Fisher-Yates — the tile Shuffle button is a display convenience, not a
// deterministic thing (unlike the puzzle's own daily tile order).
function shuffleInPlace(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

function lwToggleTile(tile) {
  if (!lw) return;
  const idx = lw.selected.indexOf(tile);
  if (idx >= 0) lw.selected.splice(idx, 1);
  else if (lw.selected.length < 4) lw.selected.push(tile);
}

function lwSubmit() {
  if (!lw || lw.selected.length !== 4) return;
  const puzzle = lw.puzzle;
  const tileGroup = lwTileGroupMap(puzzle);
  const selectedSet = new Set(lw.selected);
  const difficulties = lw.selected.map((t) => (tileGroup[t] ? tileGroup[t].difficulty : 0));
  lw.result = LinkWallLog.recordGuess(lw.day, difficulties);

  const matched = puzzle.groups.find((g) => !lw.solved.some((s) => s.label === g.label) && g.members.every((m) => selectedSet.has(m)));
  if (matched) {
    lw.result = LinkWallLog.recordSolvedGroup(lw.day, matched.label);
    lw.solved.push(matched);
    lw.remaining = lw.remaining.filter((t) => !selectedSet.has(t));
    lw.selected = [];
    lw.oneAway = null;
    if (lw.solved.length === puzzle.groups.length) lwFinish(true);
    return;
  }

  lw.result.mistakes += 1;
  LinkWallLog.save(lw.day, lw.result);
  const closest = puzzle.groups.find((g) => !lw.solved.some((s) => s.label === g.label)
    && lw.selected.filter((t) => g.members.includes(t)).length === 3);
  const oneAwayToken = ++lwOneAwayToken;
  lw.oneAway = closest ? 'One away…' : null;
  if (lw.oneAway) {
    setTimeout(() => { if (lw && lwOneAwayToken === oneAwayToken) { lw.oneAway = null; renderLinkWallBoard(); } }, 1600);
  }
  const shakeToken = ++lwShakeToken;
  lw.shaking = true;
  setTimeout(() => { if (lw && lwShakeToken === shakeToken) { lw.shaking = false; renderLinkWallBoard(); } }, 450);
  if (lw.result.mistakes >= 4) lwFinish(false);
}

// Loss reveals every remaining group; win just locks the day. Either way
// result.completed flips, so the next render swaps to the result screen.
function lwFinish(won) {
  if (!lw) return;
  const puzzle = lw.puzzle;
  if (!won) {
    const remaining = puzzle.groups.filter((g) => !lw.solved.some((s) => s.label === g.label));
    lw.solved.push(...remaining);
    lw.selected = [];
  }
  lw.result.completed = true;
  lw.result.won = won;
  LinkWallLog.save(lw.day, lw.result);
}

function linkWallResultHTML() {
  const puzzle = lw.puzzle, result = lw.result;
  const shareRows = (result.guessHistory || []).map((row) =>
    `<div class="linkwall-share-row">${row.map((d) => `<span class="linkwall-sq lw-diff-${d}"></span>`).join('')}</div>`).join('');
  const groupsReveal = puzzle.groups.map((g) => `<div class="linkwall-group-row lw-diff-${g.difficulty}">
      <div class="linkwall-group-label">${h(g.label)}</div>
      <div class="linkwall-group-why">${h(g.why)}</div>
    </div>`).join('');
  const sub = result.won
    ? `${result.mistakes} mistake${result.mistakes === 1 ? '' : 's'} — nice work.`
    : "Here's today's four groups. New wall tomorrow.";
  return `${linkWallBackHTML()}<div class="results">
    <div class="card scorecard" style="--tint:${result.won ? '#2FCB8A' : '#FF5C5C'}">
      <div class="linkwall-result-icon">${result.won ? ICON.check : ICON.xmark}</div>
      <div class="muted">${result.won ? 'SOLVED' : 'NEXT TIME'}</div>
      <div class="muted">${h(sub)}</div>
    </div>
    ${shareRows ? `<div class="card pad grid-card"><div class="linkwall-share-grid">${shareRows}</div></div>` : ''}
    <h2 class="section">Today's four groups</h2>
    ${groupsReveal}
    <button class="btn btn-blue btn-full" data-lw-share>Share</button>
    <button class="btn btn-text btn-full" data-back>Done</button>
  </div>`;
}

function bindLinkWallResultInteractions() {
  $('[data-lw-share]')?.addEventListener('click', shareLinkWall);
}

// Wordle/Connections-convention emoji share (docs/CLUB-FEATURES-BUILD.md Stage 2:
// "a shareable grid of colored squares — huge organic reach"). Web Share API with
// clipboard fallback, mirroring shareResult/shareHDYK.
async function shareLinkWall() {
  if (!lw) return;
  const { result, day } = lw;
  const EMOJI = { 1: '🟨', 2: '🟩', 3: '🟦', 4: '🟪' };
  const rows = (result.guessHistory || []).map((row) => row.map((d) => EMOJI[d] || '⬜').join('')).join('\n');
  const summary = result.won
    ? `Solved in ${result.guessHistory.length} guess${result.guessHistory.length === 1 ? '' : 'es'}.`
    : "Didn't solve it today.";
  const text = [`🧠 Tidbits Link Wall — ${day}`, rows, summary, `Play at ${SITE_URL}`].join('\n');
  try { if (navigator.share) { await navigator.share({ text }); return; } } catch {}
  try { await navigator.clipboard.writeText(text); toast('Copied to clipboard!'); } catch { toast('Copy failed'); }
}

// The Daily's global board — read from the static JSON the hourly cron publishes
// (free/cacheable, never RTDB). Shows your standing, per-question global accuracy vs
// your own marks, and the top board. Honest about the hourly cadence.
// Tidbits Club — the web promo/join surface (MONETIZATION §4a, rule 6). Sells the tier
// without ever gating the free game. Web pays via a Merchant of Record (best margin);
// R-MON-2: "already a member?" is SIGN IN, never a code field.
// R-CLUB-1 (docs/iOS-DESIGN.md §5.2a — the rule is cross-platform): the app's ONE Club
// entry point. Deliberately quiet, and placed BELOW the free surfaces. Club used to
// surface as four cards here plus three "see all" rows in Records; the count of visible
// locks, not the real free/paid ratio, is what reads as the size of the paywall.
function clubDoorCard() {
  const club = Entitlement.isClub;
  return `<a href="#/club" class="card row" style="display:flex;align-items:center;gap:12px;text-decoration:none;color:inherit;margin-top:6px">
    <span>${ICON.check}</span>
    <span style="flex:1">
      <b>Tidbits Club</b>
      <span class="muted" style="display:block;font-size:.9em">${club
        ? 'Your six Club features, all in one place.'
        : 'Six optional extras for getting better. Everything else in Tidbits is free.'}</span>
    </span><span class="chev">›</span></a>`;
}

// The member view of #/club: the hub. Non-members get the paywall below, unchanged —
// it is the only surface in the app allowed to make an offer (R-CLUB-1).
function clubHubRow(href, icon, title, subtitle) {
  return `<a href="${href}" class="card row" style="display:flex;align-items:center;gap:12px;text-decoration:none;color:inherit;margin-bottom:10px">
    <span style="width:1.5em;display:flex;align-items:center;justify-content:center">${icon}</span>
    <span style="flex:1"><b>${h(title)}</b>
      <span class="muted" style="display:block;font-size:.9em">${h(subtitle)}</span></span>
    <span class="chev">›</span></a>`;
}

// A hub row that starts a round instead of navigating (Weak-Spot, Marathon).
function clubHubLaunchRow(action, icon, title, subtitle) {
  return `<button class="card row" data-club-${action} style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;margin-bottom:10px;font:inherit;color:inherit">
    <span style="width:1.5em;display:flex;align-items:center;justify-content:center">${icon}</span>
    <span style="flex:1"><b>${h(title)}</b>
      <span class="muted" style="display:block;font-size:.9em">${h(subtitle)}</span></span>
    <span class="chev">›</span></button>`;
}

// Member copy, NOT previewLine() — those lines are written to SELL, which is exactly wrong
// aimed at someone who already paid.
function storyHubSubtitle() {
  const n = StoryArchive.count();
  return n === 0 ? 'Every story you unlock, kept here forever.'
                 : `${n} stor${n === 1 ? 'y' : 'ies'} collected — searchable, forever.`;
}

function clubHub() {
  const run = Marathon.inProgress();
  const runs = Marathon.history();
  const marathonSub = run ? `Question ${run.currentIndex + 1} of ${run.total} — resume where you left off.`
    : (runs.length ? `${Math.round((runs[0].correct / runs[0].total) * 100)}% on your last run. Start another.`
                   : '200 questions, graded by domain. Stop and resume anytime.');
  return `<div style="max-width:640px;margin:0 auto;padding:8px 0">
    <div class="card pad" style="--tint:#2FCB8A;margin-bottom:16px">
      <h1 class="view-heading">You're a member</h1>
      <p class="muted">Everything below is yours. The rest of Tidbits stays free for everyone.</p>
    </div>
    <h2 class="section">Play</h2>
    ${clubHubRow('#/linkwall', ICON.grid, 'Link Wall', "Today's board — 16 facts, 4 hidden groups.")}
    ${clubHubLaunchRow('weakspot', ICON.target, 'Weak-Spot Arena', 'A round built entirely from the questions you\'ve missed.')}
    ${clubHubLaunchRow('marathon', ICON.flag, 'Marathon', marathonSub)}
    ${clubHubRow('#/expeditions', ICON.compass, 'Expeditions', 'Multi-week campaigns through one domain.')}
    <h2 class="section">Your record</h2>
    ${clubHubRow('#/archive', ICON.book, 'Story Archive', storyHubSubtitle())}
    ${clubHubRow('#/atlas', ICON.map, 'Knowledge Atlas', 'What you actually know, by domain, over time.')}
    ${clubHubRow('#/marathon', ICON.flame, 'Marathon History', runs.length ? `${runs.length} run${runs.length === 1 ? '' : 's'} on record.` : 'Your finished runs, kept forever.')}
    <dialog id="marathon-dlg" class="night-dlg">
      <div class="night-form">
        <h2>Marathon in progress</h2>
        <p class="muted">${marathonResumeMessage()}</p>
        <div class="night-actions">
          <button type="button" class="btn" data-marathon-cancel>Cancel</button>
          <button type="button" class="btn" data-marathon-startover>Start Over</button>
          <button type="button" class="btn btn-primary" data-marathon-resume>Resume</button>
        </div>
      </div>
    </dialog>
  </div>`;
}

function viewClub() {
  if (Entitlement.isClub) return clubHub();   // R-CLUB-1: members get the hub, not a receipt
  const pillars = CLUB.pillars.map(([icon, title, blurb]) =>
    `<div style="display:flex;gap:12px;align-items:flex-start;padding:8px 0">
       <div style="font-size:1.4em;width:1.6em;text-align:center">${icon}</div>
       <div><div style="font-weight:800">${h(title)}</div><div class="muted" style="font-size:.9em">${h(blurb)}</div></div>
     </div>`).join('');
  const plans = CLUB.plans.map((p) => {
    const ready = !!p.checkout;
    return `<button class="club-plan" data-checkout="${h(p.checkout)}" ${ready ? '' : 'disabled'}
      style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;padding:16px;border-radius:16px;border:3px solid var(--color-border);background:${p.accent};color:#fff;cursor:${ready ? 'pointer' : 'default'};opacity:${ready ? 1 : 0.85};margin-bottom:10px">
      <div style="flex:1"><div style="font-weight:900;font-size:1.05em">${h(p.name)}</div><div style="opacity:.9;font-size:.85em">${h(p.tag)}</div></div>
      <div style="font-weight:900;font-size:1.3em">${h(p.price)}</div></button>`;
  }).join('');
  const billingNote = CLUB.plans.some((p) => p.checkout) ? '' :
    `<p class="muted" style="text-align:center;font-size:.85em">Secure checkout is being set up — plans go live shortly.</p>`;
  return `<div style="max-width:640px;margin:0 auto;padding:8px 0">
    <div class="card pad" style="text-align:center;--tint:#2D5BFF;margin-bottom:16px">
      <div style="font-size:2.2em">⭐️</div>
      <h1 class="view-heading">Get better, not just play more</h1>
      <p class="muted">${h(CLUB.pitch)}</p>
      <p class="muted" style="font-size:.85em"><b>The whole game stays free.</b> Club is the layer on top.</p>
    </div>
    <div class="card pad" style="margin-bottom:16px">${pillars}</div>
    ${plans}
    ${billingNote}
    <p class="muted" style="text-align:center;font-size:.85em;margin-top:12px">Bought Tidbits Club already? <a href="#/profile" style="color:var(--color-accent);font-weight:700">Sign in with the same email</a> — it's already yours.</p>
    <p class="muted" style="text-align:center;font-size:.78em;margin-top:16px;line-height:1.5">Tidbits Club Monthly and Yearly are auto-renewing subscriptions at the prices shown. Each renews automatically at the end of its period unless you cancel first; cancel anytime from your purchase-confirmation email. Founding Member is a one-time purchase for lifetime access — it does not renew.</p>
    <p class="muted" style="text-align:center;font-size:.8em;margin-top:8px"><a href="/terms.html" style="color:var(--color-accent);font-weight:700">Terms of Use</a> · <a href="/privacy.html" style="color:var(--color-accent);font-weight:700">Privacy Policy</a> · <a href="/refunds.html" style="color:var(--color-accent);font-weight:700">Refunds</a></p>
  </div>`;
}
function bindClub() {
  app.querySelectorAll('[data-checkout]').forEach((b) => b.addEventListener('click', () => {
    const url = b.dataset.checkout;
    if (url) window.open(url, '_blank', 'noopener');   // MoR hosted checkout
  }));
  // The member hub's launchers (R-CLUB-1) — these used to live on Home.
  const ws = app.querySelector('[data-club-weakspot]');
  if (ws) ws.addEventListener('click', openWeakSpot);
  const mt = app.querySelector('[data-club-marathon]');
  if (mt) mt.addEventListener('click', openMarathon);
  const dlg = app.querySelector('#marathon-dlg');
  if (dlg) {
    app.querySelector('[data-marathon-cancel]').addEventListener('click', () => dlg.close());
    app.querySelector('[data-marathon-resume]').addEventListener('click', () => { dlg.close(); startMarathonRound(false); });
    app.querySelector('[data-marathon-startover]').addEventListener('click', () => { dlg.close(); startMarathonRound(true); });
  }
}

async function renderDailyBoard() {
  const day = dayKey();
  const myScore = Number(localStorage.getItem('tidbits.dailyboard.score') || 0);
  app.innerHTML = `<div class="results"><div class="card scorecard" style="--tint:#0047FF">
    <div class="muted">DAILY · ${h(day)}</div><div class="huge">${myScore}</div>
    <div class="muted">everyone played the same set today</div></div>
    <div id="db-board" class="card pad">Loading today’s field…</div>
    <button class="btn btn-text btn-full" data-done>Done</button></div>`;
  $('[data-done]')?.addEventListener('click', () => { location.hash = '#/play'; });
  const board = $('#db-board');
  const data = await DailyBoard.results(day);
  if (!data || !data.n) {
    board.innerHTML = `<b>You’re among the first today.</b>
      <div class="muted" style="margin-top:6px">The global board refreshes every hour — check back to see where you landed.</div>`;
    return;
  }
  const pct = DailyBoard.percentile(data.hist, myScore);
  const marks = (localStorage.getItem('tidbits.dailyboard.marks') || '').padEnd(7, '?');
  const perQ = (data.perQ || []).map((rate, i) => {
    const mine = marks[i] === '1' ? '🟢' : marks[i] === '0' ? '🔴' : '⚫️';
    return `<div style="display:flex;align-items:center;gap:10px;padding:6px 0">
      <span>${mine}</span><span style="flex:1">Question ${i + 1}</span>
      <span class="muted" style="font-variant-numeric:tabular-nums">${Math.round(rate * 100)}% got it</span></div>`;
  }).join('');
  const top = (data.top || []).slice(0, 20).map((r, i) =>
    `<div style="display:flex;align-items:center;gap:10px;padding:8px 12px;border-radius:12px;background:var(--color-surface)">
      <span style="font-weight:900;width:26px;opacity:${i === 0 ? 1 : 0.5}">${i + 1}</span>
      <span style="flex:1;font-weight:700">${h(r.name || 'Player')}${i === 0 ? ' <b style="font-size:.7em;color:var(--color-primary)">TOP</b>' : ''}</span>
      <span style="font-weight:900;font-variant-numeric:tabular-nums">${r.score | 0}</span></div>`).join('');
  board.innerHTML = `${pct == null ? '' : `<div style="text-align:center;margin-bottom:10px"><span class="huge" style="font-size:2.2em">${pct}%</span><div class="muted">you beat ${pct}% of ${data.n.toLocaleString()} players today</div></div>`}
    <h2 class="section">How the world did</h2>${perQ}
    <h2 class="section">Today’s top</h2><div style="display:flex;flex-direction:column;gap:6px">${top}</div>`;
}

// L5 (charter): a hard answer you knew → invite the story + a conversation, not a passive move-on.
async function shareHDYK(a) {
  if (!a) return;
  const answer = a.q.options[a.q.correctIndex] || '';
  const text = `I knew "${a.q.prompt}" on Tidbits Trivia — it's ${answer}. How did YOU know that? 🧠\n${itemURL(a.q.id)}`;
  try { if (navigator.share) { await navigator.share({ text }); return; } } catch {}
  try { await navigator.clipboard.writeText(text); toast('Copied — go start a conversation!'); } catch { toast('Share failed'); }
}

async function shareResult(s, grid) {
  const header = game.mode.id === 'daily' ? `🧠 Tidbits Daily — ${dayKey()}` : `🧠 Tidbits — ${game.mode.title}`;
  const filled = Math.round(s.acc * 7 / 100);
  const meter = '▰'.repeat(filled) + '▱'.repeat(7 - filled);
  const day = Identity.profile?.streak?.current || 0;   // cross-context day streak (the habit metric)
  const streak = day >= 2 ? `\n🔥 ${day}-day streak` : (s.maxStreak >= 3 ? `\n🔥 Best run ${s.maxStreak}` : '');
  const text = `${header}\n${s.score} pts · ${s.correct}/${s.total}\n${meter} ${s.acc}%\n${grid}${streak}\nPlay at ${SITE_URL}`;
  try { if (navigator.share) { await navigator.share({ text }); return; } } catch {}
  try { await navigator.clipboard.writeText(text); toast('Copied to clipboard!'); } catch { toast('Copy failed'); }
}
function toast(msg) {
  const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg; document.body.appendChild(t);
  setTimeout(() => t.remove(), 1800);
}

// ---- Trivia Night HOST (web) ----------------------------------------------
// Owner architecture: the web hosts a casual Night on the SAME RTDB backend as
// Tidbits Live. Build the night with the shared loader, open live/{code}, then
// pace Reveal → Next while phones/other apps join (the unified live player) and
// auto-score. (Web has no native QR encoder, so the host shows the code + link;
// project a QR from a phone/TV/Mac host, which all render one.)
const NH = { code: '', error: '', questions: [], index: 0, revealed: false, stage: 'lobby',
             teams: {}, scores: {}, answers: {}, hostPlays: false, hostName: 'Host',
             hostChoice: null, plan: null, cat: null, unsubs: [], ansUnsub: null };
let nhRoot = null;

async function openNightHost(plan, cat) {
  Object.assign(NH, { code: '', error: '', questions: [], index: 0, revealed: false, stage: 'lobby',
    teams: {}, scores: {}, answers: {}, hostChoice: null, plan, cat, unsubs: [], ansUnsub: null,
    shuffledOrder: [], shuffledValues: [], speedBonus: false, locked: false });
  nhInjectStyles();
  if (!nhRoot) { nhRoot = document.createElement('div'); nhRoot.className = 'nh-ov'; document.body.appendChild(nhRoot); }
  drawHost();
  try { const g = new Game('barTrivia', cat, { nightPlan: plan }); await g.load(); NH.questions = g.questions || []; }
  catch { NH.error = 'Couldn’t build the night.'; drawHost(); return; }
  try {
    const r = await FirebaseNet.liveHostOpen('Trivia Night', { onError: (m) => { NH.error = m; } });
    NH.code = r.code;
    NH.unsubs.push(FirebaseNet.liveOnTeams(NH.code, (t) => { NH.teams = t || {}; drawHost(); }));
    NH.unsubs.push(FirebaseNet.liveOnScores(NH.code, (s) => { NH.scores = s || {}; drawHost(); }));
  } catch { if (!NH.error) NH.error = 'Couldn’t open a room. Check your connection.'; }
  drawHost();
}

function closeNightHost() {
  NH.unsubs.forEach((u) => { try { u(); } catch {} }); NH.unsubs = [];
  if (NH.ansUnsub) { try { NH.ansUnsub(); } catch {} NH.ansUnsub = null; }
  if (NH.code) FirebaseNet.liveClose(NH.code).catch(() => {});
  if (nhRoot) { nhRoot.remove(); nhRoot = null; }
  NH.code = ''; NH.stage = 'lobby';
}

function nhIsMCQ(q) { return !q.closest && !q.ordering && !q.matching && !q.accepted && !q.enumerate; }
function nhShuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
function nhPrepare() {
  const q = NH.questions[NH.index];
  NH.shuffledOrder = q && q.ordering ? nhShuffle([...q.ordering]) : [];
  NH.shuffledValues = q && q.matching ? nhShuffle([...q.matching.values]) : [];
}

function nhPub() {
  const q = NH.questions[NH.index];
  if (!q) return { round: 0, roundTitle: '', qid: 'end', qNum: 0, qTotal: 0, phase: 'ended', prompt: '', format: '' };
  const ri = q.roundIndex || 0;
  const inRound = NH.questions.filter((x) => (x.roundIndex || 0) === ri);
  const kind = (NH.plan.rounds[ri] || [])[0];
  const p = { round: ri + 1, roundTitle: NIGHT.roundTitle[kind] || kind || '', qid: `r${ri}q${NH.index}`,
    qNum: inRound.indexOf(q) + 1, qTotal: inRound.length, phase: NH.revealed ? 'reveal' : 'question',
    prompt: q.prompt, format: kind || 'classic' };
  if (nhIsMCQ(q)) { p.options = q.options; if (NH.revealed) p.answerIndex = q.correctIndex; }
  if (q.image) p.imageURL = q.image;
  if (q.closest) p.numeric = { min: q.closest.min, max: q.closest.max, step: q.closest.step, unit: q.closest.unit };
  if (q.ordering) p.orderItems = NH.shuffledOrder;
  if (q.matching) { p.matchKeys = q.matching.keys; p.matchValues = NH.shuffledValues; }
  if (q.enumerate) p.enumTarget = q.enumerate.groups.length;
  if (NH.locked && !NH.revealed) p.locked = true;
  return p;
}

/** Points for one submission, by type (mirrors LiveNightHost.score). */
function nhScore(q, a) {
  if (q.closest) { if (a.number == null) return 0; const err = Math.abs(a.number - q.closest.answer); return err < q.closest.tolerance ? Math.round(50 * (1 - err / q.closest.tolerance)) : 0; }
  if (q.ordering) { if (!a.order) return 0; let pts = 0; a.order.forEach((idx, pos) => { if (NH.shuffledOrder[idx] === q.ordering[pos]) pts++; }); return pts; }
  if (q.matching) { if (!a.pairs) return 0; let pts = 0; q.matching.keys.forEach((k, i) => { const vi = a.pairs[i]; if (vi != null && NH.shuffledValues[vi] === q.matching.values[i]) pts++; }); return pts; }
  if (q.accepted) return a.text && matchesAccepted(a.text, q.accepted) ? 1 : 0;
  if (q.enumerate) { if (!a.list) return 0; const filled = new Set(); for (const name of a.list) { for (let gi = 0; gi < q.enumerate.groups.length; gi++) { if (!filled.has(gi) && matchesAccepted(name, q.enumerate.groups[gi])) { filled.add(gi); break; } } } return filled.size; }
  return a.choice === q.correctIndex ? 1 : 0;
}
function nhAnswerLine(q) {
  if (q.closest) return q.closest.unit ? `${q.closest.answer} ${q.closest.unit}` : `${q.closest.answer}`;
  if (q.accepted) return q.accepted[0] || '';
  if (q.ordering) return q.ordering.join(' → ');
  if (q.matching) return q.matching.keys.map((k, i) => `${k} = ${q.matching.values[i]}`).join(', ');
  if (q.enumerate) return q.enumerate.groups.map((g) => g[0]).join(', ');
  return (q.options && q.options[q.correctIndex]) || '';
}

async function nhPublish() {
  const pub = nhPub();
  await FirebaseNet.livePublish(NH.code, pub);
  if (NH.ansUnsub) { try { NH.ansUnsub(); } catch {} }
  NH.answers = {};
  NH.ansUnsub = FirebaseNet.liveOnAnswers(NH.code, pub.qid, (a) => { NH.answers = a || {}; drawHost(); });
}

async function nhStart() {
  if (!NH.code || !NH.questions.length) return;
  if (NH.hostPlays) await FirebaseNet.liveHostJoinAsTeam(NH.code, NH.hostName || 'Host');
  NH.index = 0; NH.revealed = false; NH.locked = false; NH.hostChoice = null; NH.stage = 'playing';
  nhPrepare();
  await FirebaseNet.liveSetState(NH.code, 'live');
  await nhPublish(); drawHost();
}
async function nhLock() {
  if (NH.revealed || NH.locked) return;
  NH.locked = true;
  await FirebaseNet.livePublish(NH.code, nhPub());
  drawHost();
}
async function nhReveal() {
  if (NH.revealed) return;
  NH.revealed = true;
  await FirebaseNet.livePublish(NH.code, nhPub());
  const q = NH.questions[NH.index];
  const base = Object.entries(NH.answers).map(([uid, a]) => ({ uid, pts: a ? nhScore(q, a) : 0, ts: (a && a.ts) || 0 }));
  const bonus = {};
  if (NH.speedBonus) {
    base.filter((e) => e.pts > 0).sort((a, b) => a.ts - b.ts).forEach((e, rank) => { if (rank < 3) bonus[e.uid] = 3 - rank; });
  }
  for (const e of base) {
    const total = e.pts + (bonus[e.uid] || 0);
    if (total > 0) await FirebaseNet.liveSetScore(NH.code, e.uid, (NH.scores[e.uid] || 0) + total);
  }
  drawHost();
}
async function nhNext() {
  if (!NH.revealed) return;
  NH.revealed = false; NH.locked = false; NH.hostChoice = null; NH.index++;
  if (!NH.questions[NH.index]) { NH.stage = 'ended'; await FirebaseNet.liveSetState(NH.code, 'ended'); await FirebaseNet.livePublish(NH.code, nhPub()); }
  else { nhPrepare(); await nhPublish(); }
  drawHost();
}
async function nhAnswer(i) {
  if (!NH.hostPlays || NH.revealed || NH.hostChoice != null) return;
  NH.hostChoice = i;
  await FirebaseNet.liveHostAnswer(NH.code, nhPub().qid, i);
  drawHost();
}

function nhStandings() {
  return Object.entries(NH.teams).map(([uid, t]) => ({ uid, name: (t && t.name) || 'Team', score: NH.scores[uid] || 0 }))
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
}

function drawHost() {
  if (!nhRoot) return;
  const st = nhStandings();
  const standings = `<div class="nh-stand"><div class="muted">STANDINGS</div>${st.length ? st.map((t, i) =>
    `<div class="nh-row"><span>${t.score === Math.max(...st.map(x => x.score)) ? '👑 ' : ''}${h(t.name)}</span><b>${t.score}</b></div>`).join('') :
    '<div class="muted">Players appear here as they join.</div>'}</div>`;

  if (NH.stage === 'ended') {
    // A tie is a real outcome — sorting by score and naming st[0] "the winner"
    // reported an arbitrary sort order as a victory (mirrors Core/StandingsOutcome).
    const nhTop = st.length ? Math.max(...st.map(t => t.score)) : 0;
    const nhWon = st.filter(t => t.score === nhTop).map(t => t.name);
    const nhHead = !nhWon.length ? "That's a night!"
      : nhWon.length === 1 ? h(nhWon[0]) + ' wins!'
      : nhWon.length === st.length ? "It's a tie!"
      : 'Tie \u2014 ' + nhWon.map(h).join(' &amp; ');
    nhRoot.innerHTML = `<div class="nh-card"><h1>${nhHead}</h1>${standings}
      <button class="btn btn-primary" id="nh-done">Done</button></div>`;
    nhRoot.querySelector('#nh-done').addEventListener('click', closeNightHost);
    return;
  }
  if (NH.stage === 'lobby') {
    nhRoot.innerHTML = `<div class="nh-card">
      <button class="nh-x" id="nh-x" aria-label="Close">✕</button>
      <div class="nh-badge">TRIVIA NIGHT</div>
      <p class="muted">Players join at</p>
      <a class="nh-link" href="${SITE_URL}/live/${NH.code}" target="_blank" rel="noopener">tidbitstrivia.com/live</a>
      <div class="nh-code">${NH.code || '····'}</div>
      ${NH.error ? `<div class="nh-err">${h(NH.error)}</div>` : ''}
      ${standings}
      <label class="nh-toggle"><input type="checkbox" id="nh-plays" ${NH.hostPlays ? 'checked' : ''}> I'll play too</label>
      ${NH.hostPlays ? `<input class="nh-in" id="nh-name" placeholder="Your name" value="${h(NH.hostName)}">` : ''}
      <label class="nh-toggle"><input type="checkbox" id="nh-speed" ${NH.speedBonus ? 'checked' : ''}> Speed bonus (fastest +3/+2/+1)</label>
      <button class="btn btn-primary" id="nh-start" ${NH.code ? '' : 'disabled'}>${NH.code ? 'Start the Night' : 'Opening room…'}</button>
      <p class="muted">You run the questions; everyone answers on their own device.</p>
    </div>`;
    nhRoot.querySelector('#nh-x').addEventListener('click', closeNightHost);
    nhRoot.querySelector('#nh-start').addEventListener('click', nhStart);
    nhRoot.querySelector('#nh-plays').addEventListener('change', (e) => { NH.hostPlays = e.target.checked; drawHost(); });
    nhRoot.querySelector('#nh-speed')?.addEventListener('change', (e) => { NH.speedBonus = e.target.checked; });
    const nm = nhRoot.querySelector('#nh-name'); if (nm) nm.addEventListener('input', (e) => { NH.hostName = e.target.value; });
    return;
  }
  // playing
  const p = nhPub();
  const q = NH.questions[NH.index];
  const img = p.imageURL ? `<img class="nh-img" src="${h(p.imageURL)}" alt="">` : '';
  let body;
  if (nhIsMCQ(q)) {
    const opts = (p.options || []).map((o, i) => {
      const chosen = NH.hostChoice === i;
      const correct = NH.revealed && i === q.correctIndex;
      const wrong = NH.revealed && chosen && !correct;
      const cls = ['nh-opt', chosen ? 'chosen' : '', correct ? 'correct' : '', wrong ? 'wrong' : ''].join(' ');
      const dis = (!NH.hostPlays || NH.revealed || NH.hostChoice != null) ? 'disabled' : '';
      return `<button class="${cls}" data-nhopt="${i}" ${dis}><span class="nh-optn">${i + 1}</span>${h(o)}</button>`;
    }).join('');
    body = `<div class="nh-opts">${opts}</div>`;
  } else {
    body = `<p class="muted">Players answer on their devices. Reveal when everyone's in.</p>${NH.revealed ? `<div class="nh-answer">Answer: ${h(nhAnswerLine(q))}</div>` : ''}`;
  }
  nhRoot.innerHTML = `<div class="nh-play">
    <div class="nh-head"><div class="nh-badge">CODE ${NH.code}</div><div class="muted">${Object.keys(NH.answers).length} answered</div>
      <button class="nh-x" id="nh-x" aria-label="End">✕</button></div>
    <div class="nh-round">ROUND ${p.round}/${NH.plan.rounds.length} · ${h(p.roundTitle)} — Q${p.qNum}/${p.qTotal}</div>
    ${img}
    <div class="nh-q">${h(p.prompt)}</div>
    ${body}
    ${NH.locked && !NH.revealed ? '<div class="nh-answer" style="background:#FF5C35">Answers locked — pencils down!</div>' : ''}
    <div class="nh-actions">${NH.revealed
      ? '<button class="btn btn-primary" id="nh-next">Next</button>'
      : `${NH.locked ? '' : '<button class="btn" id="nh-lock">Lock</button> '}<button class="btn btn-primary" id="nh-reveal">Reveal</button>`}</div>
    ${standings}
  </div>`;
  nhRoot.querySelector('#nh-x').addEventListener('click', closeNightHost);
  const lk = nhRoot.querySelector('#nh-lock'); if (lk) lk.addEventListener('click', nhLock);
  const rv = nhRoot.querySelector('#nh-reveal'); if (rv) rv.addEventListener('click', nhReveal);
  const nx = nhRoot.querySelector('#nh-next'); if (nx) nx.addEventListener('click', nhNext);
  nhRoot.querySelectorAll('[data-nhopt]').forEach((b) => b.addEventListener('click', () => nhAnswer(+b.dataset.nhopt)));
}

function nhInjectStyles() {
  if (document.getElementById('nh-styles')) return;
  const s = document.createElement('style'); s.id = 'nh-styles';
  s.textContent = `
  .nh-ov{position:fixed;inset:0;z-index:9999;background:var(--color-bg,#FCF5E9);display:flex;flex-direction:column;overflow-y:auto}
  .nh-card{margin:auto;max-width:460px;width:calc(100% - 40px);padding:28px;text-align:center;position:relative}
  .nh-play{max-width:680px;width:100%;margin:0 auto;padding:16px;position:relative}
  .nh-badge{display:inline-block;font-weight:900;letter-spacing:.08em;font-size:.8rem;color:#fff;background:var(--color-primary,#FF746F);padding:5px 12px;border-radius:999px;border:2.5px solid #231E1A}
  .nh-code{font-family:ui-monospace,monospace;font-weight:900;font-size:3rem;letter-spacing:.3em;color:#231E1A;margin:6px 0}
  .nh-link{font-weight:800;color:var(--color-accent,#2D5BFF);text-decoration:none}
  .nh-err{color:#c0392b;font-weight:700;margin:6px 0}
  .nh-x{position:absolute;top:12px;right:12px;width:34px;height:34px;border-radius:999px;border:2.5px solid #231E1A;background:#fff;font-weight:900;cursor:pointer}
  .nh-toggle{display:flex;align-items:center;gap:8px;justify-content:center;font-weight:700;margin:10px 0;color:#231E1A}
  .nh-in{display:block;width:100%;box-sizing:border-box;margin:8px 0;padding:12px;border:2.5px solid #231E1A;border-radius:12px;font-weight:700}
  .nh-head{display:flex;align-items:center;gap:12px;padding:4px 0 12px}
  .nh-round{font-weight:800;color:#8a8078;margin:6px 0}
  .nh-q{font-weight:900;font-size:1.5rem;line-height:1.25;color:#231E1A;margin:6px 0 16px}
  .nh-img{display:block;max-width:100%;max-height:260px;border-radius:12px;margin:6px 0}
  .nh-answer{font-weight:900;color:#231E1A;background:#3CCB8A;border-radius:12px;padding:12px;margin-bottom:14px}
  .nh-opts{display:flex;flex-direction:column;gap:10px;margin-bottom:14px}
  .nh-opt{display:flex;align-items:center;gap:12px;text-align:left;padding:14px;font-size:1.05rem;font-weight:800;color:#231E1A;background:#fff;border:2.5px solid #231E1A;border-radius:14px;box-shadow:3px 3px 0 #231E1A;cursor:pointer}
  .nh-opt:disabled{cursor:default}.nh-opt.chosen{background:#DDE3FF}.nh-opt.correct{background:#3CCB8A;color:#fff}.nh-opt.wrong{background:#f3d1cd}
  .nh-optn{display:inline-flex;width:26px;height:26px;align-items:center;justify-content:center;border-radius:8px;background:#231E1A;color:#fff;font-weight:900;font-size:.9rem;flex:none}
  .nh-actions{display:flex;gap:10px;margin-bottom:14px}
  .nh-stand{text-align:left;margin-top:10px;border-top:2px solid var(--color-border,#E7DFD2);padding-top:10px}
  .nh-row{display:flex;justify-content:space-between;padding:6px 0;font-weight:800;color:#231E1A}`;
  document.head.appendChild(s);
}

boot();
