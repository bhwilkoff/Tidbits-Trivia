// Tidbits Live — web player. Join a Mac-hosted pub event by code, answer on your
// phone, watch your score. Mirrors the iOS/Android join and the LiveRoom contract
// (docs/LIVE-ROOM-CONTRACT.md). Self-managing full-screen overlay so it needs no
// changes to the main render loop; the big-screen QR points here (#/live/CODE).
import { FirebaseNet } from './firebase.js';
import { Identity } from './identity.js';

const S = { code: '', team: '', joined: false, joining: false, pub: null, meta: null,
            score: 0, wager: 0, blurred: false, submittedQid: null, chosen: null, error: '', local: {},
            liveAnswered: 0, liveCorrect: 0, talliedQid: null, recorded: false };

// Wave C: flag if the player switches tab / backgrounds mid-question before submitting.
document.addEventListener('visibilitychange', () => {
  if (document.hidden && S.pub?.phase === 'question' && S.submittedQid !== S.pub?.qid) S.blurred = true;
});

// Live→profile bridge: feed the portable identity once when the night ends.
function recordIfEnded() {
  if (!S.joined || S.recorded) return;
  if (S.meta?.state !== 'ended' && S.pub?.phase !== 'ended') return;
  S.recorded = true;
  Identity.recordLiveGame(S.liveCorrect, S.liveAnswered);
  Identity.recordStanding(S.meta?.venue || '', S.score || 0);   // Wave E: per-venue season standing
  captureCoplayers();   // L5 social graph: remember who you played with
}

/// G7: group the room's joins into teams, the SAME rule as Swift LiveTeamRoster
/// and its C# mirror — fold surrounding space, case and runs of whitespace, but
/// NOT punctuation ("St. Elmo" and "St Elmo" are plausibly different tables, and
/// merging is destructive in a way splitting is not). The display name is the
/// LEADER's spelling; ties on joinedAt break on uid so every stack agrees.
function rosterTeams(teams) {
  const byKey = {};
  for (const [uid, t] of Object.entries(teams || {})) {
    const name = (t?.name || '');
    const key = name.trim().toLowerCase().split(/\s+/).filter(Boolean).join(' ');
    if (!key) continue;
    (byKey[key] ||= []).push({ uid, name, joinedAt: t?.joinedAt || 0 });
  }
  return Object.entries(byKey).map(([key, ms]) => {
    ms.sort((a, b) => (a.joinedAt - b.joinedAt) || (a.uid < b.uid ? -1 : 1));
    return { key, name: ms[0].name, size: ms.length };
  }).sort((a, b) => a.name.localeCompare(b.name));
}

/// G7: the teams already in the room, so a second phone at a table can JOIN it
/// instead of quietly starting a near-identical second team.
async function loadRoomTeams(code) {
  try {
    S.roomTeams = rosterTeams(await FirebaseNet.liveTeams(code));
  } catch { S.roomTeams = []; }
  draw();
}

// L5: read the room roster once at night-end and stash the co-players (uid + name + venue),
// so the "Add the people you played with" surface can offer to connect with them.
async function captureCoplayers() {
  try {
    const teams = await FirebaseNet.liveTeams(S.code);
    const me = Identity.authUid, now = Date.now();
    const list = JSON.parse(localStorage.getItem('tidbits.coplayers') || '{}');
    for (const [uid, t] of Object.entries(teams || {})) {
      if (!uid || uid === me) continue;
      list[uid] = { uid, name: t?.name || 'Player', venue: S.meta?.venue || '', at: now };
    }
    const recent = Object.values(list).sort((a, b) => b.at - a.at).slice(0, 30);
    const obj = {}; for (const c of recent) obj[c.uid] = c;
    localStorage.setItem('tidbits.coplayers', JSON.stringify(obj));
    draw();
  } catch {}
}

export function recentCoplayers() {
  try { return Object.values(JSON.parse(localStorage.getItem('tidbits.coplayers') || '{}')).sort((a, b) => b.at - a.at); }
  catch { return []; }
}
let root = null, unsubs = [];

export function openLive(code = '') {
  S.code = (code || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);
  // Pre-fill for an easy rejoin after a reload/restart (the anon uid persists,
  // so the team's score is intact). The Firebase SDK auto-reconnects a live
  // subscription through a transient drop with no action needed.
  try {
    if (!S.code) S.code = (localStorage.getItem('tidbits.live.code') || '');
    if (!S.team) S.team = (localStorage.getItem('tidbits.live.team') || '');
  } catch { /* private mode */ }
  injectStyles();
  if (!root) { root = document.createElement('div'); root.className = 'live-ov'; document.body.appendChild(root); }
  draw();
}

// Pure teardown — the router calls this when the hash leaves #/live. Idempotent.
export function closeLive() {
  if (!root && unsubs.length === 0) return;
  unsubs.forEach((u) => { try { u(); } catch {} }); unsubs = [];
  if (S.code && S.joined) FirebaseNet.liveLeave(S.code).catch(() => {});
  if (root) { root.remove(); root = null; }
  Object.assign(S, { joined: false, joining: false, pub: null, meta: null, score: 0, submittedQid: null, chosen: null, error: '' });
}

async function join() {
  const team = (document.getElementById('live-team')?.value || '').trim();
  const code = (document.getElementById('live-code')?.value || '').trim().toUpperCase();
  if (code.length < 4) { S.error = 'Enter the 4-letter code from the screen.'; return draw(); }
  if (!team) { S.error = 'Enter a team name.'; return draw(); }
  S.code = code; S.team = team; S.joining = true; S.error = ''; draw();
  try {
    await FirebaseNet.liveJoin(code, team, { onError: (m) => { S.error = m; } });
    S.joined = true; S.joining = false;
    S.liveAnswered = 0; S.liveCorrect = 0; S.talliedQid = null; S.recorded = false;
    try { localStorage.setItem('tidbits.live.code', code); localStorage.setItem('tidbits.live.team', team); } catch { /* private mode */ }
    unsubs.push(FirebaseNet.liveOnMeta(code, (m) => {
      // F-010: a host RESTART on the same code is a new session whose
      // positional qids (r0q0…) collide with the old one — qid-keyed
      // submission state would leave this client "Locked in" on a question
      // it never answered. createdAt is the session identity.
      if (m && S.meta && m.createdAt !== S.meta.createdAt) {
        S.submittedQid = null; S.chosen = null; S.local = {}; S.blurred = false;
        S.liveAnswered = 0; S.liveCorrect = 0; S.talliedQid = null;
      }
      S.meta = m; recordIfEnded(); draw();
    }));
    unsubs.push(FirebaseNet.liveOnScore(code, (v) => { S.score = v; draw(); }));
    unsubs.push(FirebaseNet.liveOnPub(code, (p) => {
      if (p && p.qid !== S.pub?.qid) { S.submittedQid = null; S.chosen = null; S.local = {}; S.blurred = false; }   // Wave C: reset focus flag
      S.pub = p;
      if (p && p.phase === 'reveal' && S.talliedQid !== p.qid) {   // tally MCQ accuracy at reveal
        S.talliedQid = p.qid;
        if (p.options && S.submittedQid === p.qid) { S.liveAnswered++; if (S.chosen === p.answerIndex) S.liveCorrect++; }
      }
      recordIfEnded(); draw();
    }));
    draw();
  } catch (e) {
    S.joining = false;
    if (!S.error) S.error = 'Couldn’t join. Check the code and your connection.';
    draw();
  }
}

async function submitAns(fields) {
  if (!S.pub || S.pub.phase !== 'question' || S.submittedQid === S.pub.qid || S.pub.locked) return;
  if (S.pub.wager) fields = { ...fields, wager: Math.max(0, Math.min(S.wager || 0, S.score || 0)) };   // Wave A: attach the stake
  if (S.blurred) fields = { ...fields, blurred: true };   // Wave C: flag mid-question tab-switch
  S.submittedQid = S.pub.qid; draw();
  try { await FirebaseNet.liveSubmit(S.code, S.pub.qid, fields); }
  catch { S.submittedQid = null; S.chosen = null; S.error = 'Answer didn’t send — tap again.'; draw(); }
}
async function pick(i) { S.chosen = i; submitAns({ choice: i }); }
/// G1: buzz in. An EMPTY payload — on a buzz round the answer is said out loud to
/// the room, so all the wire needs is who was first, and the server stamps that.
async function buzz() { submitAns({}); }

// Wave A: the stake input on a wager question — bet 0…your score.
function wagerHTML() {
  const maxBet = Math.max(0, S.score || 0);
  const w = Math.min(S.wager || 0, maxBet);
  return `<div class="live-wager">
    <div class="live-wager-label">YOUR WAGER</div>
    ${maxBet === 0 ? `<div class="live-sub">No points to wager yet.</div>`
      : `<input id="live-wager-range" type="range" min="0" max="${maxBet}" step="1" value="${w}">
         <div class="live-wager-val"><span id="live-wager-num">${w}</span> of ${maxBet} pts</div>`}
  </div>`;
}

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

// Wave A: tick the countdown element to the host's deadline (self-clears when it's gone).
let _liveTimerInt = null;
function ensureLiveTimer() {
  if (_liveTimerInt) return;
  const tick = () => {
    const el = document.getElementById('live-timer');
    if (!el) { clearInterval(_liveTimerInt); _liveTimerInt = null; return; }
    const secs = Math.max(0, Math.ceil((+el.dataset.dl - Date.now()) / 1000));
    el.textContent = secs >= 60 ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}` : `${secs}s`;
    el.style.color = secs <= 5 ? '#FF5C35' : 'var(--color-text)';
  };
  tick();
  _liveTimerInt = setInterval(tick, 500);
}

function draw() {
  if (!root) return;
  root.innerHTML = S.remote ? remoteHTML() : (S.joined ? playHTML() : joinHTML());
  if (S.remote) {
    root.querySelector('#rmt-go')?.addEventListener('click', remotePair);
    root.querySelectorAll('[data-rmt]').forEach((b) =>
      b.addEventListener('click', () => remoteSend(b.dataset.rmt)));
    root.querySelector('#live-x')?.addEventListener('click', () => { location.hash = '#/play'; });
    return;
  }
  if (document.getElementById('live-timer')) ensureLiveTimer();
  const wr = document.getElementById('live-wager-range');   // Wave A: wager slider
  if (wr) wr.oninput = (e) => { S.wager = +e.target.value; const n = document.getElementById('live-wager-num'); if (n) n.textContent = e.target.value; };
  if (!S.joined) {
    root.querySelector('#live-join')?.addEventListener('click', join);
    root.querySelector('#live-hostrmt')?.addEventListener('click', () => { S.remote = true; S.error = ''; draw(); });
    root.querySelector('#live-code')?.addEventListener('input', (e) => {
      e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);
      // G7: look the room up as soon as the code is complete, so the teams are on
      // screen BEFORE the player commits to a name.
      S.code = e.target.value;
      if (e.target.value.length === 4) loadRoomTeams(e.target.value);
      else if ((S.roomTeams || []).length) { S.roomTeams = []; draw(); }
    });
    // Tapping a team fills in the LEADER's spelling, which is what keeps the
    // table one row instead of two near-identical ones.
    root.querySelectorAll('[data-team]').forEach((b) => b.addEventListener('click', () => {
      S.team = b.dataset.team;
      const f = document.getElementById('live-team');
      if (f) f.value = S.team;
    }));
  }
  root.querySelector('#live-x')?.addEventListener('click', () => { location.hash = '#/play'; });
  root.querySelectorAll('[data-opt]').forEach((b) => b.addEventListener('click', () => pick(+b.dataset.opt)));
  root.querySelector('#live-buzz')?.addEventListener('click', buzz);
  root.querySelectorAll('[data-add]').forEach((b) => b.addEventListener('click', async () => {   // L5 social graph
    await Identity.addFriend(b.dataset.add, b.dataset.name, ''); draw();
  }));

  const p = S.pub;
  root.querySelector('#live-range')?.addEventListener('input', (e) => {
    S.local.num = +e.target.value;
    const d = root.querySelector('#live-numval'); if (d) d.textContent = `${S.local.num}${p?.numeric?.unit ? ' ' + p.numeric.unit : ''}`;
  });
  root.querySelector('#live-text')?.addEventListener('input', (e) => { S.local.text = e.target.value; });
  root.querySelectorAll('.live-mv').forEach((b) => b.addEventListener('click', () => {
    const [pos, dir] = b.dataset.mv.split(':').map(Number);
    const order = S.local.order || (p.orderItems || []).map((_, i) => i);
    const n = pos + dir;
    if (n >= 0 && n < order.length) { [order[pos], order[n]] = [order[n], order[pos]]; S.local.order = order; draw(); }
  }));
  root.querySelectorAll('.live-sel').forEach((sel) => sel.addEventListener('change', (e) => {
    const i = +sel.dataset.key; const pairs = S.local.pairs || (p.matchKeys || []).map(() => -1);
    pairs[i] = +e.target.value; S.local.pairs = pairs;
  }));
  root.querySelector('#live-add')?.addEventListener('click', () => {
    const t = (root.querySelector('#live-enum')?.value || '').trim();
    const items = S.local.enumItems || [];
    if (t && !items.some((x) => x.toLowerCase() === t.toLowerCase())) { items.push(t); S.local.enumItems = items; draw(); }
  });
  root.querySelector('#live-submit')?.addEventListener('click', () => {
    if (!p) return;
    if (p.numeric) submitAns({ number: S.local.num != null ? S.local.num : Math.round((p.numeric.min + p.numeric.max) / 2) });
    else if (p.orderItems) submitAns({ order: S.local.order || p.orderItems.map((_, i) => i) });
    else if (p.matchKeys) { const pairs = S.local.pairs || p.matchKeys.map(() => -1); if (pairs.some((v) => v < 0)) return; submitAns({ pairs }); }
    else if (p.enumTarget != null) { const items = S.local.enumItems || []; if (!items.length) return; submitAns({ list: items }); }
    else { const t = (root.querySelector('#live-text')?.value || '').trim(); if (t) submitAns({ text: t }); }
  });
}

/// G6 — the host's phone remote.
///
/// A SEPARATE surface, not a mode on the joiner, because a remote is not a
/// player: it has no team, no score, and must not be able to submit an answer.
/// Sharing the joiner's state machine would put an answer path one bug away from
/// a device that is standing next to the projector.
function remoteHTML() {
  if (!S.remotePaired) {
    return `<div class="live-card">
      <button id="live-x" class="live-x" aria-label="Close">✕</button>
      <div class="live-badge">HOST REMOTE</div>
      <h1>Drive the night</h1>
      <p class="live-sub">Enter your room code and the PIN from your laptop.</p>
      <input id="rmt-code" class="live-in live-codein" placeholder="CODE" maxlength="4" value="${esc(S.code)}" autocapitalize="characters" autocomplete="off">
      <input id="rmt-pin" class="live-in live-codein" placeholder="PIN" maxlength="6" inputmode="numeric" value="${esc(S.remotePin)}">
      ${S.error ? `<div class="live-err">${esc(S.error)}</div>` : ''}
      <button id="rmt-go" class="live-go">Pair</button>
      <p class="live-sub" style="margin-top:14px">The PIN is on the host screen, not the projector — the room code alone cannot drive the show.</p>
    </div>`;
  }
  const p = S.pub || {};
  return `<div class="live-play">
    <div class="live-round">REMOTE · ${esc(S.code)}${p.round ? ` · ROUND ${p.round}` : ''}</div>
    <div class="live-q">${esc(p.prompt || 'Waiting for the host…')}</div>
    ${p.phase === 'reveal' && p.options && typeof p.answerIndex === 'number'
      ? `<div class="live-rmtanswer">Answer: ${esc(p.options[p.answerIndex] || '')}</div>` : ''}
    <div class="live-rmtgrid">
      <button class="live-rmtbtn" data-rmt="reveal">Reveal</button>
      <button class="live-rmtbtn" data-rmt="next">Next</button>
      <button class="live-rmtbtn" data-rmt="skip">Skip</button>
      <button class="live-rmtbtn" data-rmt="scores">Scores</button>
    </div>
    ${S.remoteNote ? `<div class="live-sub">${esc(S.remoteNote)}</div>` : ''}
  </div>`;
}

async function remotePair() {
  const code = (document.getElementById('rmt-code')?.value || '').trim().toUpperCase();
  const pin = (document.getElementById('rmt-pin')?.value || '').trim();
  if (code.length < 4) { S.error = 'Enter the 4-letter room code.'; return draw(); }
  if (pin.length < 6) { S.error = 'Enter the 6-digit PIN from your laptop.'; return draw(); }
  S.code = code; S.remotePin = pin; S.error = '';
  // Resume from the HOST's counter. A fresh remote that started at 1 would be
  // refused forever once the host had run anything.
  S.remoteId = await FirebaseNet.liveRemoteLastId(code);
  S.remotePaired = true;
  FirebaseNet.liveOnPub(code, (p) => { S.pub = p; draw(); });
  draw();
}

async function remoteSend(verb) {
  S.remoteId = (S.remoteId || 0) + 1;
  try {
    await FirebaseNet.liveRemoteSend(S.code, { id: S.remoteId, verb, pin: S.remotePin });
    S.remoteNote = '';
  } catch {
    // The command did not land, so do NOT keep the id: reusing it next press is
    // correct, and advancing it would leave a gap the host silently skips past.
    S.remoteId -= 1;
    S.remoteNote = 'That did not send — try again.';
  }
  draw();
}

function joinHTML() {
  return `<div class="live-card">
    <button id="live-x" class="live-x" aria-label="Close">✕</button>
    <div class="live-badge">TIDBITS LIVE</div>
    <h1>Join the game</h1>
    <p class="live-sub">Enter the code on the big screen.</p>
    <input id="live-code" class="live-in live-codein" placeholder="CODE" maxlength="4" value="${esc(S.code)}" autocapitalize="characters" autocomplete="off">
    <input id="live-team" class="live-in" placeholder="Your team name" value="${esc(S.team)}" maxlength="24">
    ${(S.roomTeams || []).length ? `<div class="live-teams"><div class="live-teamshead">Already playing — tap to join your table</div>` +
      S.roomTeams.map(t => `<button class="live-teamchip" data-team="${esc(t.name)}">${esc(t.size > 1 ? `${t.name} · ${t.size}` : t.name)}</button>`).join('') +
      `</div>` : ''}
    ${S.error ? `<div class="live-err">${esc(S.error)}</div>` : ''}
    <button id="live-join" class="live-go" ${S.joining ? 'disabled' : ''}>${S.joining ? 'Joining…' : 'Join'}</button>
    <button id="live-hostrmt" class="live-hostrmt">I'm the host — use this phone as a remote</button>
  </div>`;
}

// L5: "Add the people you played with" — the freshly-captured co-players, minus those already added.
function coplayersHTML() {
  const co = recentCoplayers().slice(0, 12);
  if (!co.length) return '';
  const rows = co.map((c) => {
    const added = Identity.isFriend(c.uid);
    return `<div style="display:flex;align-items:center;gap:10px;padding:8px 12px;background:rgba(255,255,255,.08);border-radius:12px;margin:4px 0">
      <span style="flex:1;font-weight:700">${esc(c.name)}</span>
      ${added ? `<span style="opacity:.7;font-size:.85em">Added ✓</span>`
              : `<button data-add="${esc(c.uid)}" data-name="${esc(c.name)}" style="padding:6px 14px;font-weight:800;border:2px solid #fff;border-radius:10px;background:transparent;color:#fff;cursor:pointer">Add</button>`}
    </div>`;
  }).join('');
  return `<div style="margin:16px 0;max-width:340px;width:100%"><div class="live-sub" style="margin-bottom:6px">Add the people you played with</div>${rows}</div>`;
}

function playHTML() {
  const p = S.pub;
  const head = `<div class="live-head">
      <div><div class="live-team">${esc(S.team)}</div><div class="live-code2">CODE ${esc(S.code)}</div></div>
      <div class="live-score"><span>${S.score}</span><small>points</small></div>
      <button id="live-x" class="live-x" aria-label="Leave">✕</button>
    </div>`;

  if (!p || (S.meta && S.meta.state === 'lobby')) {
    return `<div class="live-play">${head}<div class="live-center"><div class="live-badge">YOU'RE IN</div>
      <h2>Waiting for the host to start…</h2><p class="live-sub">Keep this open — questions appear here.</p></div></div>`;
  }
  if (p.phase === 'ended' || (S.meta && S.meta.state === 'ended')) {
    return `<div class="live-play">${head}<div class="live-center"><div class="live-badge">THAT'S A WRAP</div>
      <h2>Final score: ${S.score}</h2><p class="live-sub">Thanks for playing. ${esc(S.meta?.venue || '')}</p>
      ${coplayersHTML()}
      <button id="live-x" class="live-go">Done</button></div></div>`;
  }

  const revealed = p.phase === 'reveal';
  const answered = S.submittedQid === p.qid;
  const status = revealed
    ? `<div class="live-note ok">Answer revealed — check your score.</div>`
    : (answered ? `<div class="live-note ok">Locked in — waiting for the reveal…</div>`
       : p.locked ? `<div class="live-note" style="color:#FF5C35">Answers locked — pencils down!</div>`
       : `<div class="live-note">Answer below.</div>`);
  const img = p.imageURL ? `<img class="live-img" src="${esc(p.imageURL)}" alt="">` : '';

  return `<div class="live-play">${head}
    <div class="live-round">ROUND ${p.round} · ${esc(p.roundTitle)} — Q${p.qNum}/${p.qTotal}</div>
    ${p.letter ? `<div class="live-letter">EVERY ANSWER BEGINS WITH ${esc(String(p.letter).toUpperCase()[0])}</div>` : ''}
    ${img}
    <div class="live-q">${esc(p.prompt)}</div>
    ${!revealed && p.deadline ? `<div id="live-timer" data-dl="${p.deadline}" style="font-size:30px;font-weight:900;text-align:center;margin:6px 0;font-variant-numeric:tabular-nums"></div>` : ''}
    ${!revealed && p.wager ? wagerHTML() : ''}
    ${answerHTML(p, revealed)}
    ${status}
    ${revealed && p.story ? `<div style="margin-top:12px;padding:12px 14px;border-radius:12px;background:var(--color-surface);line-height:1.5;color:var(--color-text)">${esc(p.story)}</div>` : ''}
  </div>`;
}

/** The right answer input for the question type. The host scores each on reveal. */
function answerHTML(p, revealed) {
  const locked = revealed || S.submittedQid === p.qid || p.locked === true;
  // G1: on a BUZZ round the whole answer UI is one big button, and the normal
  // options must be GONE — a player who can both buzz and pick an option has two
  // ways to answer and the host adjudicates the wrong one. The payload is empty
  // on purpose: the answer is spoken out loud, so the wire only carries who was
  // first, ordered by the SERVER stamp.
  // G5: the pick-a-category grid is up, so there is no live question. The answer
  // buttons must be GONE — leaving them left the room able to answer the previous
  // question while the host was waiting for a pick.
  if (p.phase === 'board' && p.board) {
    const b = p.board;
    const head = b.chooser ? `${esc(b.chooser)} picks` : 'Pick a category';
    const rows = (b.tiers || []).map(t =>
      `<div class="live-boardrow">` +
      (b.categories || []).map((_, i) =>
        `<span class="live-boardcell${(b.taken || []).includes(i + ':' + t) ? ' taken' : ''}">${t * 100}</span>`
      ).join('') + `</div>`).join('');
    return `<div class="live-board"><div class="live-boardhead">${head}</div>` +
           `<div class="live-boardcols">${(b.categories || []).map(c => `<span>${esc(c)}</span>`).join('')}</div>` +
           rows +
           `<div class="live-boardfoot">${b.remaining} left · ${b.points} points on the board</div></div>`;
  }
  if (p.buzz && !revealed) {
    return S.submittedQid === p.qid
      ? '<div class="live-buzzed">Buzzed — wait for the host</div>'
      : '<button id="live-buzz" class="live-buzz">BUZZ</button>';
  }
  const L = S.local;
  const submit = locked ? '' : '<button id="live-submit" class="live-go">Submit</button>';
  if (p.options) {
    return `<div class="live-opts">${p.options.map((o, i) => {
      const chosen = S.chosen === i;
      const correct = revealed && p.answerIndex === i;
      const wrong = revealed && chosen && p.answerIndex !== i;
      const cls = ['live-opt', chosen ? 'chosen' : '', correct ? 'correct' : '', wrong ? 'wrong' : ''].join(' ');
      return `<button class="${cls}" data-opt="${i}" ${locked ? 'disabled' : ''}><span class="live-optnum">${i + 1}</span>${esc(o)}</button>`;
    }).join('')}</div>`;
  }
  if (p.numeric) {
    const n = p.numeric;
    const val = L.num != null ? L.num : Math.round((n.min + n.max) / 2);
    return `<div class="live-num" id="live-numval">${val}${n.unit ? ' ' + esc(n.unit) : ''}</div>
      <input id="live-range" class="live-range" type="range" min="${n.min}" max="${n.max}" step="${n.step || 1}" value="${val}" ${locked ? 'disabled' : ''}>${submit}`;
  }
  if (p.orderItems) {
    const order = L.order || p.orderItems.map((_, i) => i);
    return `<div class="live-order">${order.map((idx, pos) =>
      `<div class="live-orow"><span class="live-onum">${pos + 1}.</span><span class="live-oname">${esc(p.orderItems[idx])}</span>${locked ? '' : `<button class="live-mv" data-mv="${pos}:-1">▲</button><button class="live-mv" data-mv="${pos}:1">▼</button>`}</div>`).join('')}</div>${submit}`;
  }
  if (p.matchKeys && p.matchValues) {
    const pairs = L.pairs || p.matchKeys.map(() => -1);
    return `<div class="live-match">${p.matchKeys.map((k, i) =>
      `<div class="live-mrow"><span>${esc(k)}</span><select class="live-sel" data-key="${i}" ${locked ? 'disabled' : ''}><option value="-1">Choose…</option>${p.matchValues.map((v, vi) => `<option value="${vi}" ${pairs[i] === vi ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select></div>`).join('')}</div>${submit}`;
  }
  if (p.enumTarget != null) {
    const items = L.enumItems || [];
    return `<p class="live-sub">Name as many as you can (${items.length}${p.enumTarget ? '/' + p.enumTarget : ''})</p>
      ${items.length ? `<div class="live-chips">${items.map(esc).join(' · ')}</div>` : ''}
      ${locked ? '' : `<div class="live-addrow"><input id="live-enum" class="live-in" placeholder="Add one…"><button id="live-add" class="live-go">Add</button></div><button id="live-submit" class="live-go">Done</button>`}`;
  }
  return `<input id="live-text" class="live-in" placeholder="Type your answer" value="${esc(L.text || '')}" ${locked ? 'disabled' : ''}>${submit}`;
}

function injectStyles() {
  if (document.getElementById('live-styles')) return;
  const s = document.createElement('style');
  s.id = 'live-styles';
  s.textContent = `
  .live-ov{position:fixed;inset:0;z-index:9999;background:var(--color-bg,#FCF5E9);display:flex;flex-direction:column;overflow-y:auto;-webkit-overflow-scrolling:touch}
  .live-card{margin:auto;max-width:420px;width:calc(100% - 40px);padding:28px;text-align:center}
  .live-badge{display:inline-block;font-weight:900;letter-spacing:.08em;font-size:.8rem;color:#fff;background:var(--color-primary,#FF746F);padding:5px 12px;border-radius:999px;border:2.5px solid #231E1A}
  .live-card h1,.live-center h2{font-weight:900;margin:14px 0 4px;color:var(--color-text,#231E1A)}
  .live-sub{color:#8a8078;margin:0 0 18px}
  .live-in{display:block;width:100%;box-sizing:border-box;margin:10px 0;padding:14px 16px;font-size:1.1rem;border:2.5px solid #231E1A;border-radius:14px;background:#fff;font-weight:700;color:#231E1A}
  .live-codein{text-align:center;letter-spacing:.4em;font-size:1.6rem;font-weight:900;font-family:ui-monospace,monospace}
  .live-go{margin-top:12px;width:100%;padding:15px;font-size:1.1rem;font-weight:900;color:#fff;background:var(--color-primary,#FF746F);border:2.5px solid #231E1A;border-radius:16px;box-shadow:4px 4px 0 #231E1A;cursor:pointer}
  .live-go:disabled{opacity:.6}
  .live-err{color:#c0392b;font-weight:700;margin:6px 0}
  .live-x{position:absolute;top:16px;right:16px;width:34px;height:34px;border-radius:999px;border:2.5px solid #231E1A;background:#fff;font-weight:900;cursor:pointer;color:#231E1A}
  .live-wager{margin:10px 0;padding:12px;border-radius:12px;background:rgba(255,92,53,.12)}
  .live-wager-label{font-weight:800;font-size:.8rem;color:#FF5C35;letter-spacing:.04em}
  .live-wager input[type=range]{width:100%;margin:8px 0;accent-color:#FF5C35}
  .live-wager-val{font-weight:900;font-size:1.3rem;color:#231E1A}
  .live-play{padding:16px;max-width:640px;width:100%;margin:0 auto;position:relative}
  .live-head{display:flex;align-items:center;gap:12px;padding:6px 0 14px}
  .live-team{font-weight:900;font-size:1.15rem;color:#231E1A}
  .live-code2{font-family:ui-monospace,monospace;color:#8a8078;font-weight:700;font-size:.8rem}
  .live-score{margin-left:auto;text-align:right;line-height:1}.live-score span{font-weight:900;font-size:1.8rem;color:#231E1A}.live-score small{display:block;color:#8a8078;font-weight:700}
  .live-round{font-weight:800;color:#8a8078;letter-spacing:.03em;margin:8px 0}
  .live-letter{font-weight:900;color:var(--color-primary,#FF746F);letter-spacing:.04em;margin:-4px 0 8px}
  .live-board{margin:10px 0}
  .live-boardhead{font-weight:900;font-size:1.2rem;color:var(--color-primary,#FF746F);text-align:center;margin-bottom:8px}
  .live-boardcols{display:flex;gap:4px;margin-bottom:4px}
  .live-boardcols span{flex:1;text-align:center;font-size:.68rem;font-weight:800;color:#8a8078;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .live-boardrow{display:flex;gap:4px;margin-bottom:4px}
  .live-boardcell{flex:1;text-align:center;padding:9px 0;border-radius:8px;background:#fff;border:2px solid #231E1A;font-weight:900}
  .live-boardcell.taken{opacity:.28;border-style:dashed}
  .live-boardfoot{text-align:center;font-weight:700;color:#8a8078;margin-top:6px}
  .live-teams{margin:6px 0 2px}
  .live-teamshead{font-size:.72rem;font-weight:800;color:#8a8078;margin-bottom:6px}
  .live-teamchip{display:inline-block;margin:0 6px 6px 0;padding:7px 12px;border-radius:999px;border:2.5px solid #231E1A;background:#fff;font-weight:800;cursor:pointer;font-size:.85rem}
  .live-hostrmt{display:block;width:100%;margin-top:10px;padding:11px;border:0;background:none;color:#8a8078;font-weight:700;text-decoration:underline;cursor:pointer}
  .live-rmtgrid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:18px}
  .live-rmtbtn{padding:22px 10px;font-size:1.15rem;font-weight:900;color:#fff;background:var(--color-primary,#FF746F);border:2.5px solid #231E1A;border-radius:16px;box-shadow:4px 4px 0 #231E1A;cursor:pointer}
  .live-rmtanswer{margin-top:10px;font-weight:900;color:#1E9E6A}
  .live-q{font-weight:900;font-size:1.5rem;line-height:1.25;color:#231E1A;margin:6px 0 20px}
  .live-opts{display:flex;flex-direction:column;gap:12px}
  .live-opt{display:flex;align-items:center;gap:12px;text-align:left;padding:16px;font-size:1.1rem;font-weight:800;color:#231E1A;background:#fff;border:2.5px solid #231E1A;border-radius:16px;box-shadow:4px 4px 0 #231E1A;cursor:pointer}
  /* G1: the buzz button is the whole screen's worth of target — the player is
     racing and watching the big screen, not hunting a small control. */
  .live-buzz{display:block;width:100%;padding:44px 0;font-size:2.6rem;font-weight:900;letter-spacing:.04em;color:#fff;background:#FF5C35;border:2.5px solid #231E1A;border-radius:20px;box-shadow:5px 5px 0 #231E1A;cursor:pointer}
  .live-buzz:active{transform:translate(3px,3px);box-shadow:2px 2px 0 #231E1A}
  .live-buzzed{padding:34px 0;text-align:center;font-size:1.3rem;font-weight:900;color:#128a5b}
  .live-opt:disabled{cursor:default}
  .live-opt.chosen{background:#DDE3FF}
  .live-opt.correct{background:#3CCB8A;color:#fff}
  .live-opt.wrong{background:#f3d1cd}
  .live-optnum{display:inline-flex;width:26px;height:26px;align-items:center;justify-content:center;border-radius:8px;background:#231E1A;color:#fff;font-weight:900;font-size:.9rem;flex:none}
  .live-img{display:block;max-width:100%;max-height:260px;border-radius:12px;margin:6px 0}
  .live-num{font-weight:900;font-size:1.8rem;color:#231E1A;text-align:center;margin:6px 0}
  .live-range{width:100%;margin:6px 0 12px}
  .live-order,.live-match{display:flex;flex-direction:column;gap:8px;margin-bottom:12px}
  .live-orow,.live-mrow{display:flex;align-items:center;gap:8px;padding:10px 12px;border:2.5px solid #231E1A;border-radius:12px;background:#fff}
  .live-onum{font-weight:900;color:#8a8078}.live-oname{flex:1;font-weight:800;color:#231E1A}
  .live-mrow>span:first-child{flex:1;font-weight:800;color:#231E1A}
  .live-mv{width:34px;height:34px;border:2px solid #231E1A;border-radius:8px;background:#fff;font-weight:900;cursor:pointer}
  .live-sel{padding:8px;border:2px solid #231E1A;border-radius:8px;font-weight:700;background:#fff}
  .live-chips{font-weight:800;color:#231E1A;margin:6px 0}
  .live-addrow{display:flex;gap:8px;align-items:center}.live-addrow .live-in{margin:0}.live-addrow .live-go{width:auto;margin:0;padding:12px 18px}
  .live-note{margin-top:18px;text-align:center;font-weight:800;color:#8a8078}
  .live-note.ok{color:#2f9e6f}.live-note.miss{color:#c0392b}
  .live-center{text-align:center;padding:40px 16px}`;
  document.head.appendChild(s);
}
