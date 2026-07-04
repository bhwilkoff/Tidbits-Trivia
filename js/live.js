// Tidbits Live — web player. Join a Mac-hosted pub event by code, answer on your
// phone, watch your score. Mirrors the iOS/Android join and the LiveRoom contract
// (docs/LIVE-ROOM-CONTRACT.md). Self-managing full-screen overlay so it needs no
// changes to the main render loop; the big-screen QR points here (#/live/CODE).
import { FirebaseNet } from './firebase.js';

const S = { code: '', team: '', joined: false, joining: false, pub: null, meta: null,
            score: 0, submittedQid: null, chosen: null, error: '', local: {} };
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
    try { localStorage.setItem('tidbits.live.code', code); localStorage.setItem('tidbits.live.team', team); } catch { /* private mode */ }
    unsubs.push(FirebaseNet.liveOnMeta(code, (m) => { S.meta = m; draw(); }));
    unsubs.push(FirebaseNet.liveOnScore(code, (v) => { S.score = v; draw(); }));
    unsubs.push(FirebaseNet.liveOnPub(code, (p) => {
      if (p && p.qid !== S.pub?.qid) { S.submittedQid = null; S.chosen = null; S.local = {}; }
      S.pub = p; draw();
    }));
    draw();
  } catch (e) {
    S.joining = false;
    if (!S.error) S.error = 'Couldn’t join. Check the code and your connection.';
    draw();
  }
}

async function submitAns(fields) {
  if (!S.pub || S.pub.phase !== 'question' || S.submittedQid === S.pub.qid) return;
  S.submittedQid = S.pub.qid; draw();
  try { await FirebaseNet.liveSubmit(S.code, S.pub.qid, fields); }
  catch { S.submittedQid = null; S.chosen = null; S.error = 'Answer didn’t send — tap again.'; draw(); }
}
async function pick(i) { S.chosen = i; submitAns({ choice: i }); }

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

function draw() {
  if (!root) return;
  root.innerHTML = S.joined ? playHTML() : joinHTML();
  if (!S.joined) {
    root.querySelector('#live-join')?.addEventListener('click', join);
    root.querySelector('#live-code')?.addEventListener('input', (e) => {
      e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);
    });
  }
  root.querySelector('#live-x')?.addEventListener('click', () => { location.hash = '#/play'; });
  root.querySelectorAll('[data-opt]').forEach((b) => b.addEventListener('click', () => pick(+b.dataset.opt)));

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

function joinHTML() {
  return `<div class="live-card">
    <button id="live-x" class="live-x" aria-label="Close">✕</button>
    <div class="live-badge">TIDBITS LIVE</div>
    <h1>Join the game</h1>
    <p class="live-sub">Enter the code on the big screen.</p>
    <input id="live-code" class="live-in live-codein" placeholder="CODE" maxlength="4" value="${esc(S.code)}" autocapitalize="characters" autocomplete="off">
    <input id="live-team" class="live-in" placeholder="Your team name" value="${esc(S.team)}" maxlength="24">
    ${S.error ? `<div class="live-err">${esc(S.error)}</div>` : ''}
    <button id="live-join" class="live-go" ${S.joining ? 'disabled' : ''}>${S.joining ? 'Joining…' : 'Join'}</button>
  </div>`;
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
      <button id="live-x" class="live-go">Done</button></div></div>`;
  }

  const revealed = p.phase === 'reveal';
  const answered = S.submittedQid === p.qid;
  const status = revealed
    ? `<div class="live-note ok">Answer revealed — check your score.</div>`
    : (answered ? `<div class="live-note ok">Locked in — waiting for the reveal…</div>`
       : `<div class="live-note">Answer below.</div>`);
  const img = p.imageURL ? `<img class="live-img" src="${esc(p.imageURL)}" alt="">` : '';

  return `<div class="live-play">${head}
    <div class="live-round">ROUND ${p.round} · ${esc(p.roundTitle)} — Q${p.qNum}/${p.qTotal}</div>
    ${img}
    <div class="live-q">${esc(p.prompt)}</div>
    ${answerHTML(p, revealed)}
    ${status}
  </div>`;
}

/** The right answer input for the question type. The host scores each on reveal. */
function answerHTML(p, revealed) {
  const locked = revealed || S.submittedQid === p.qid;
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
  .live-play{padding:16px;max-width:640px;width:100%;margin:0 auto;position:relative}
  .live-head{display:flex;align-items:center;gap:12px;padding:6px 0 14px}
  .live-team{font-weight:900;font-size:1.15rem;color:#231E1A}
  .live-code2{font-family:ui-monospace,monospace;color:#8a8078;font-weight:700;font-size:.8rem}
  .live-score{margin-left:auto;text-align:right;line-height:1}.live-score span{font-weight:900;font-size:1.8rem;color:#231E1A}.live-score small{display:block;color:#8a8078;font-weight:700}
  .live-round{font-weight:800;color:#8a8078;letter-spacing:.03em;margin:8px 0}
  .live-q{font-weight:900;font-size:1.5rem;line-height:1.25;color:#231E1A;margin:6px 0 20px}
  .live-opts{display:flex;flex-direction:column;gap:12px}
  .live-opt{display:flex;align-items:center;gap:12px;text-align:left;padding:16px;font-size:1.1rem;font-weight:800;color:#231E1A;background:#fff;border:2.5px solid #231E1A;border-radius:16px;box-shadow:4px 4px 0 #231E1A;cursor:pointer}
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
