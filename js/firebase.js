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
  // Persist the session across reloads. getAuth defaults to local persistence, but be
  // explicit so a refresh always restores the signed-in user.
  try { await auth.setPersistence(_auth, auth.browserLocalPersistence); } catch {}
  // CRITICAL: wait for Firebase to restore any PERSISTED user (federated OR anon) before
  // deciding whether to create an anonymous one. Calling signInAnonymously() while a
  // Google/Apple user is persisted REPLACES it — a silent logout + a brand-new uid on every
  // page refresh (records stop sticking). Only mint an anon when nobody is signed in.
  await new Promise((resolve) => {
    const unsub = auth.onAuthStateChanged(_auth, (u) => { unsub(); resolve(u); });
  });
  if (_auth.currentUser) {
    _uid = _auth.currentUser.uid;
  } else {
    const cred = await auth.signInAnonymously(_auth);   // throws if the provider is disabled
    _uid = cred.user.uid;
  }
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

  // Portable player identity (players/{uid}) — see js/identity.js.
  async ensureUid() { await ensure(); return _uid; },
  async loadProfile(uid) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `players/${uid}`));
    return snap.exists() ? snap.val() : null;
  },
  async saveProfile(uid, profile) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `players/${uid}`), profile);
  },
  async deleteProfile(uid) {
    const { db } = await ensure();
    try { await db.remove(db.ref(_db, `players/${uid}`)); } catch { /* rules may forbid post-switch */ }
  },
  isSignedIn() { return !!(_auth && _auth.currentUser && !_auth.currentUser.isAnonymous); },
  currentEmail() { return (_auth && _auth.currentUser && _auth.currentUser.email) || null; },

  // Wave E: per-venue season standing (standings/{season}/{venue}/{uid}) — keyed by AUTH uid.
  async loadStanding(path) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, path));
    return snap.exists() ? snap.val() : null;
  },
  async saveStanding(path, obj) {
    const { db } = await ensure();
    await db.set(db.ref(_db, path), obj);
  },

  // Social graph (L5): a private friends list under the owner-only playersPrivate bucket (no rule change).
  async loadFriends(uid) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `playersPrivate/${uid}/friends`));
    return snap.exists() ? snap.val() : {};
  },
  async setFriend(uid, friendUid, obj) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `playersPrivate/${uid}/friends/${friendUid}`), obj);
  },
  async removeFriend(uid, friendUid) {
    const { db } = await ensure();
    await db.remove(db.ref(_db, `playersPrivate/${uid}/friends/${friendUid}`));
  },

  // L5 async friend duels: a duel = one shared question set, both players answer on their own time.
  async createDuel(id, obj) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `duels/${id}`), obj);
  },
  async loadDuel(id) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `duels/${id}`));
    return snap.exists() ? snap.val() : null;
  },
  async submitDuelPlayer(id, uid, slot) {   // each player writes ONLY their own players/{uid} slot (rules)
    const { db } = await ensure();
    await db.set(db.ref(_db, `duels/${id}/players/${uid}`), slot);
  },
  async sendDuelInvite(toUid, duelId, obj) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `duelInbox/${toUid}/${duelId}`), obj);
  },
  async loadDuelInbox(uid) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `duelInbox/${uid}`));
    return snap.exists() ? snap.val() : {};
  },
  async clearDuelInvite(uid, duelId) {
    const { db } = await ensure();
    await db.remove(db.ref(_db, `duelInbox/${uid}/${duelId}`));
  },

  // Sign out of the federated account and return to a FRESH anonymous session (new uid).
  // The account's records stay in players/{accountUid}; signing back in restores them.
  async signOutUser() {
    const { auth } = await ensure();
    await auth.signOut(_auth);
    const cred = await auth.signInAnonymously(_auth);
    _uid = cred.user.uid;
    return _uid;
  },

  // Federated sign-in (Apple/Google). With allowDuplicateEmails on, each provider gets
  // its own uid even for the same email; identity keys the profile by the VERIFIED email
  // so both providers share records. Returns { uid, email }.
  async signInFederated(providerId) {
    const { auth } = await ensure();
    const provider = providerId === 'apple.com' ? new auth.OAuthProvider('apple.com') : new auth.GoogleAuthProvider();
    if (providerId === 'apple.com') { provider.addScope('email'); provider.addScope('name'); }
    const result = await auth.signInWithPopup(_auth, provider);
    _uid = result.user.uid;
    return { uid: _uid, email: result.user.email, displayName: result.user.displayName };
  },

  // Ownership proof for the email-keyed profile: emailOwners/{key} = the verified email.
  // The players/{key} write rule requires this to match auth.token.email.
  async setEmailOwner(accountKey, email) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `emailOwners/${accountKey}`), email);
  },

  // The Daily's global board (docs/DAILY-BOARD-CONTRACT.md): one write per player per day
  // to dailyBoard/{day}/{uid}. Keyed by the auth uid (rules: own-uid write only), NOT the
  // account key — a single device plays the Daily once; sign-in isn't required to compete.
  async submitDailyBoard(day, row) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `dailyBoard/${day}/${_uid}`), row);
  },

  // Live listener on a profile (cross-device sync). Returns an unsubscribe fn.
  onProfile(key, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `players/${key}`), (snap) => cb(snap.val()));
  },

  // Synced daily log (dayKey → score) — so "done today" + the archive follow the identity.
  async setDailyScore(key, day, score) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `dailyLog/${key}/${day}`), score);
  },
  async loadDailyLog(key) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `dailyLog/${key}`));
    return snap.exists() ? snap.val() : {};
  },

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
  // L5 social graph: read the room roster once (uid → {name}) to capture co-players at night-end.
  async liveTeams(code) {
    const { db } = await ensure();
    const snap = await db.get(db.ref(_db, `live/${code}/teams`));
    return snap.exists() ? snap.val() : {};
  },
  async liveLeave(code) {
    if (!_fns) return;
    const { ref, remove } = _fns.db;
    try { await remove(ref(_db, `live/${code}/teams/${_uid}`)); } catch { /* best effort */ }
  },

  // --- HOST side (this device opens live/{code} and owns meta/pub/scores) ---
  // The web can now HOST a casual Trivia Night on the same backend as Tidbits
  // Live (owner architecture). Mirrors LiveNightHost (Swift) + FirebaseNet
  // (Android). The rich Tidbits Live host stays macOS-only.
  async liveHostOpen(name, { onError } = {}) {
    try {
      const { db } = await ensure();
      const code = newCode();
      await db.set(db.ref(_db, `live/${code}/meta`),
        { host: _uid, createdAt: Date.now(), name: name || 'Trivia Night', venue: '', state: 'lobby' });
      return { code, uid: _uid };
    } catch (e) { onError && onError(authHint(e)); throw e; }
  },
  async livePublish(code, pub) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `live/${code}/pub`), pub);
  },
  async liveSetState(code, state) {
    const { db } = await ensure();
    await db.update(db.ref(_db, `live/${code}/meta`), { state });
  },
  async liveSetScore(code, uid, score) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `live/${code}/scores/${uid}`), Math.max(0, score | 0));
  },
  liveOnTeams(code, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/teams`), (s) => cb(s.val() || {}));
  },
  liveOnScores(code, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/scores`), (s) => cb(s.val() || {}));
  },
  liveOnAnswers(code, qid, cb) {
    const { ref, onValue } = _fns.db;
    return onValue(ref(_db, `live/${code}/answers/${qid}`), (s) => cb(s.val() || {}));
  },
  // Host-plays-too: the host registers as a team + answers under its own uid.
  async liveHostJoinAsTeam(code, name) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `live/${code}/teams/${_uid}`), { name: name || 'Host', joinedAt: Date.now() });
  },
  async liveHostAnswer(code, qid, choice) {
    const { db } = await ensure();
    await db.set(db.ref(_db, `live/${code}/answers/${qid}/${_uid}`), { choice, ts: Date.now() });
  },
  async liveClose(code) {
    if (!_fns) return;
    const { ref, remove } = _fns.db;
    try { await remove(ref(_db, `live/${code}`)); } catch { /* best effort */ }
  },
};

function authHint(e) {
  const msg = (e && e.message) || String(e);
  if (/configuration-not-found|operation-not-allowed|admin-restricted/i.test(msg)) {
    return 'Online play needs Anonymous sign-in enabled in Firebase (owner setup).';
  }
  return 'Couldn’t reach the match server. Check your connection.';
}
