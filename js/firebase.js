// Online Quick Match over Firebase Realtime Database (Decision 040) — Android +
// web (Apple online rides GameKit, Decision 039). Firebase JS SDK is lazy-loaded
// from the CDN on first use so the offline/PWA path and initial load are
// untouched. Trust model matches local Trivia Night: a room code gates entry,
// each device runs its own engine over the shared question set and self-reports
// its score to a leader-elected coordinator. Anonymous auth gives each device a
// uid so Security Rules can scope writes; no accounts, no PII.
import { FIREBASE_CONFIG } from './firebase-config.js';

const SDK = 'https://www.gstatic.com/firebasejs/10.12.2';
let _app, _db, _auth, _uid, _fns;

async function ensure() {
  if (_db) return _fns;
  const [app, db, auth] = await Promise.all([
    import(`${SDK}/firebase-app.js`),
    import(`${SDK}/firebase-database.js`),
    import(`${SDK}/firebase-auth.js`),
  ]);
  _app = app.initializeApp(FIREBASE_CONFIG);
  _db = db.getDatabase(_app);
  _auth = auth.getAuth(_app);
  const cred = await auth.signInAnonymously(_auth);   // throws if provider disabled
  _uid = cred.user.uid;
  _fns = { db, auth };
  return _fns;
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function newCode() {
  let s = '';
  for (let i = 0; i < 4; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return s;
}

export const FirebaseNet = {
  get uid() { return _uid; },
  available: true,

  // Quick Match: claim a waiting room via a transaction (first writer becomes
  // the joiner of an existing open room; otherwise create one and wait). Returns
  // { roomId, isLeader }.
  async quickMatch(name, { onError } = {}) {
    try {
      const { db } = await ensure();
      const queueRef = db.ref(_db, 'queue/mixed');
      let joinedRoom = null;
      // Try to grab the oldest waiting room id.
      await db.runTransaction(queueRef, (cur) => {
        if (cur && cur.roomId && cur.host !== _uid) { joinedRoom = cur.roomId; return null; } // claim it
        return cur; // leave as-is; we'll create below
      });
      if (joinedRoom) return { roomId: joinedRoom, isLeader: false };
      // No open room — create one and advertise it.
      const roomId = newCode();
      const now = Date.now();
      await db.set(db.ref(_db, `rooms/${roomId}/meta`), { host: _uid, createdAt: now, state: 'lobby' });
      await db.set(db.ref(_db, `rooms/${roomId}/players/${_uid}`), { name: name || 'Player', score: 0, joinedAt: now });
      await db.set(queueRef, { roomId, host: _uid, ts: now });
      return { roomId, isLeader: true };
    } catch (e) {
      onError && onError(authHint(e));
      throw e;
    }
  },

  // Join by explicit code (private match / friend room).
  async joinRoom(roomId, name) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `rooms/${roomId}/players/${_uid}`), { name: name || 'Player', score: 0, joinedAt: Date.now() });
    return { roomId, isLeader: false };
  },

  // Live roster (players node). Returns an unsubscribe fn.
  onRoster(roomId, cb) {
    const { ref, onValue } = _fns.db;
    const r = ref(_db, `rooms/${roomId}/players`);
    return onValue(r, (snap) => cb(snap.val() || {}));
  },

  // Room meta (state machine: lobby → playing → finished, + question set).
  onMeta(roomId, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `rooms/${roomId}/meta`), (snap) => cb(snap.val() || {}));
  },
  async setMeta(roomId, patch) {
    const { ref, update } = _fns.db;
    await update(ref(_db, `rooms/${roomId}/meta`), patch);
  },

  async reportScore(roomId, score, done) {
    const { ref, update } = _fns.db;
    await update(ref(_db, `rooms/${roomId}/players/${_uid}`), { score, done: !!done });
  },

  async leave(roomId) {
    if (!_fns) return;
    const { ref, remove } = _fns.db;
    try { await remove(ref(_db, `rooms/${roomId}/players/${_uid}`)); } catch { /* best effort */ }
  },

  // ---- Tidbits Live: join a Mac-hosted pub event (live/{code}) ----
  // Contract: docs/LIVE-ROOM-CONTRACT.md. The player owns teams/{uid} +
  // answers/{qid}/{uid}; the host owns meta/pub/scores.
  async liveJoin(code, teamName, { onError } = {}) {
    try {
      const { db } = await ensure();
      await db.set(db.ref(_db, `live/${code}/teams/${_uid}`), { name: teamName || 'Team', joinedAt: Date.now() });
      return { code, uid: _uid };
    } catch (e) { onError && onError(authHint(e)); throw e; }
  },
  liveOnPub(code, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/pub`), (s) => cb(s.val()));
  },
  liveOnMeta(code, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/meta`), (s) => cb(s.val()));
  },
  liveOnScore(code, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/scores/${_uid}`), (s) => cb(s.val() || 0));
  },
  async liveSubmit(code, qid, answer) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `live/${code}/answers/${qid}/${_uid}`), { ...answer, ts: Date.now() });
  },
  async liveLeave(code) {
    if (!_fns) return;
    const { ref, remove } = _fns.db;
    try { await remove(ref(_db, `live/${code}/teams/${_uid}`)); } catch { /* best effort */ }
  },
};

function authHint(e) {
  const msg = (e && e.message) || String(e);
  if (/configuration-not-found|operation-not-allowed|admin-restricted/i.test(msg)) {
    return 'Online play needs Anonymous sign-in enabled in Firebase (owner setup).';
  }
  return 'Couldn’t reach the match server. Check your connection.';
}
