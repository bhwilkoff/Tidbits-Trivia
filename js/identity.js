// js/identity.js — the portable Tidbits player identity (web). ONE shared cross-platform
// profile at players/{uid}, the twin of PlayerIdentity.swift / PlayerIdentity.kt. Firebase
// JS persists the anonymous uid (IndexedDB), so the profile is stable across sessions.
// Rating + streak logic is byte-identical to the Swift/Kotlin versions.
import { FirebaseNet } from './firebase.js';

const ESTABLISHED_AT = 15;
const LS_KEY = 'tidbits.profile';

export const Identity = {
  profileId: null,
  profile: null,
  _subs: [],
  onChange(fn) { this._subs.push(fn); if (this.profile) { try { fn(this.profile); } catch {} } },
  _emit() { this._subs.forEach((f) => { try { f(this.profile); } catch {} }); },

  // Local-first: show a cached/local profile immediately, then reconcile with the cloud.
  // Signed-in users are keyed by their VERIFIED email (so Apple + Google share records);
  // anonymous users stay keyed by uid until they sign in.
  async bootstrap() {
    try { const c = JSON.parse(localStorage.getItem(LS_KEY) || 'null'); if (c) { this.profile = c; this._emit(); } } catch {}
    try {
      const uid = await FirebaseNet.ensureUid();
      const email = FirebaseNet.currentEmail();
      if (FirebaseNet.isSignedIn() && email) {
        const key = await accountKey(email);
        this.profileId = key;
        let remote = await FirebaseNet.loadProfile(key);
        if (!remote) {                                  // migrate an older uid-keyed profile
          const base = (await FirebaseNet.loadProfile(uid)) || this.profile || newProfile();
          await FirebaseNet.setEmailOwner(key, email);
          await FirebaseNet.saveProfile(key, base);
          remote = base;
        }
        this.profile = remote;
      } else {
        this.profileId = uid;
        const remote = await FirebaseNet.loadProfile(uid);
        this.profile = remote || this.profile || newProfile();
        if (!remote) { try { await FirebaseNet.saveProfile(uid, this.profile); } catch {} }
      }
      if (this.profileId) this._watch(this.profileId);
      this._save(); this._emit();
      this.loadFriends();   // L5 social graph: pull the private friends list (fire-and-forget)
    } catch {
      if (!this.profile) { this.profile = newProfile(); this._save(); this._emit(); }
    }
  },

  // A finished solo game moves the rating + streak + stats.
  recordGame(correct, total, live = false) {
    if (!this.profile || total <= 0) return;
    const p = this.profile;
    p.rating = updatedRating(p.rating, correct / total, live ? 1.5 : 1.0);
    p.streak = playedStreak(p.streak, today(), live);
    p.stats.gamesPlayed++; p.stats.questionsAnswered += total; p.stats.correct += correct;
    if (live) p.stats.liveNights++;
    this._persist();
  },

  // A finished LIVE game — a live night keeps the streak (+freeze) and counts; MCQ
  // accuracy nudges the rating when available.
  recordLiveGame(correct, answered) {
    if (!this.profile) return;
    const p = this.profile;
    if (answered > 0) { p.rating = updatedRating(p.rating, correct / answered, 1.5); p.stats.questionsAnswered += answered; p.stats.correct += correct; }
    p.streak = playedStreak(p.streak, today(), true);
    p.stats.gamesPlayed++; p.stats.liveNights++;
    this._persist();
  },

  // Wave E: write this player's cumulative per-venue season standing after a live night —
  // keyed by the AUTH uid (the standings rule requires auth.uid === $uid). The $0 cron
  // aggregates these into the static cross-venue leaderboard.
  async recordStanding(venue, score) {
    const vk = venueKey(venue);
    const uid = FirebaseNet.uid;
    if (!vk || !(score > 0) || !this.profile || !uid) return;
    const path = `standings/${currentSeason()}/${vk}/${uid}`;
    try {
      const existing = await FirebaseNet.loadStanding(path);
      await FirebaseNet.saveStanding(path, {
        name: this.profile.name,
        score: (existing?.score || 0) + score,
        nights: (existing?.nights || 0) + 1,
        updatedAt: Date.now(),
      });
    } catch {}
  },

  rename(name) {
    if (!this.profile) return;
    const t = (name || '').trim().slice(0, 24); if (!t) return;
    this.profile.name = t; this._persist();
  },

  // L4 cosmetics: re-roll the avatar seed → a new deterministic hue. Persists + syncs like rename.
  rerollAvatar() {
    if (!this.profile) return;
    this.profile.avatarSeed = Math.random().toString(36).slice(2, 10); this._persist();
  },

  // Social graph (L5): a private "people I've played with / follow" list. Their standings come
  // from the already-public leaderboard; the list itself lives under owner-only playersPrivate.
  _friends: JSON.parse(localStorage.getItem('tidbits.friends') || '{}'),
  friends() {
    return Object.entries(this._friends).map(([uid, v]) => ({ uid, ...v })).sort((a, b) => (b.since || 0) - (a.since || 0));
  },
  isFriend(uid) { return !!(uid && this._friends[uid]); },
  async addFriend(uid, name, avatarSeed) {
    if (!uid || uid === this.authUid || this._friends[uid]) return;
    this._friends[uid] = { name: name || 'Player', avatarSeed: avatarSeed || '', since: Date.now() };
    localStorage.setItem('tidbits.friends', JSON.stringify(this._friends));
    const me = this.authUid; if (me) { try { await FirebaseNet.setFriend(me, uid, this._friends[uid]); } catch {} }
  },
  async removeFriend(uid) {
    if (!this._friends[uid]) return;
    delete this._friends[uid];
    localStorage.setItem('tidbits.friends', JSON.stringify(this._friends));
    const me = this.authUid; if (me) { try { await FirebaseNet.removeFriend(me, uid); } catch {} }
  },
  async loadFriends() {
    const me = this.authUid; if (!me) return;
    try {
      const remote = await FirebaseNet.loadFriends(me);
      if (remote && typeof remote === 'object') { this._friends = remote; localStorage.setItem('tidbits.friends', JSON.stringify(remote)); }
    } catch {}
  },

  get signedIn() { return FirebaseNet.isSignedIn(); },
  get email() { return FirebaseNet.currentEmail(); },
  get authUid() { return FirebaseNet.uid; },   // Wave E: the standings/leaderboard are keyed by the AUTH uid

  // Daily log sync — when signed in, a daily completion also lands in dailyLog/{key} so
  // "done today" + the archive follow you across devices. Anonymous stays local-only.
  async syncDailyScore(day, score) {
    if (this.signedIn && this.profileId) { try { await FirebaseNet.setDailyScore(this.profileId, day, score); } catch {} }
  },
  async fetchDailyLog() {
    if (this.signedIn && this.profileId) { try { return (await FirebaseNet.loadDailyLog(this.profileId)) || {}; } catch {} }
    return {};
  },

  // Sign in with Apple/Google → key the profile by the verified email so BOTH providers
  // (and every device) share one record set. Merges this device's anonymous activity into
  // the email-keyed profile the first time; the guard prevents ever re-merging.
  async signIn(providerId) {
    if (this.signedIn) return false;   // already on a durable account — never re-merge the same records
    const local = this.profile || newProfile();
    const res = await FirebaseNet.signInFederated(providerId);   // { uid, email }
    if (!res.email) {                                            // no email (rare) — uid-keyed fallback
      this.profileId = res.uid;
      await FirebaseNet.saveProfile(res.uid, local);
      this._watch(res.uid);
      this._save(); this._emit();
      return false;
    }
    const key = await accountKey(res.email);
    await FirebaseNet.setEmailOwner(key, res.email);
    const existing = await FirebaseNet.loadProfile(key);
    this.profile = existing ? mergeProfiles(local, existing) : local;
    if (isDefaultName(this.profile.name) && res.displayName) this.profile.name = res.displayName.trim().slice(0, 24);   // (A) adopt provider name
    this.profileId = key;
    await FirebaseNet.saveProfile(key, this.profile);
    this._watch(key);
    this._save(); this._emit();
    return !!existing;
  },

  // (B) Live cross-device sync — a remote profile change (e.g. a rename on another device)
  // updates this one in place. Re-pointed on bootstrap / sign-in / sign-out.
  _profileUnsub: null,
  _watch(key) {
    if (this._profileUnsub) { try { this._profileUnsub(); } catch {} this._profileUnsub = null; }
    try {
      this._profileUnsub = FirebaseNet.onProfile(key, (val) => {   // name-only: avoids a stats revert if mid-game elsewhere
        if (val && val.name && this.profile && val.name !== this.profile.name) { this.profile.name = val.name; this._save(); this._emit(); }
      });
    } catch {}
  },

  // Delete the account for real — App Store 5.1.1(v) and Play both require it, and the
  // requirement applies whether or not the player ever signed in, because Tidbits
  // provisions a real anonymous account for everyone. Mirror of Swift
  // PlayerIdentityStore.deleteAccount() / Kotlin deleteAccount(): every account-keyed
  // node, then the credential, then the local state, then a fresh anonymous identity.
  //
  // The node deletes are best-effort and the credential delete is not: a node the rules
  // refuse still leaves an orphan row nobody can read, but a credential that survives is
  // an account that was not deleted, so THAT failure is surfaced.
  deleteError: null,
  async deleteAccount() {
    this.deleteError = null;
    const key = this.profileId;
    const authUid = this.authUid;
    const drop = async (path) => { try { await FirebaseNet.removePath(path); } catch {} };

    if (key) {
      await drop(`players/${key}`);
      await drop(`dailyLog/${key}`);
      await drop(`emailOwners/${key}`);
    }
    if (authUid) {
      await drop(`playersPrivate/${authUid}`);
      await drop(`pushTokens/${authUid}`);
      for (const day of Object.keys(readLocal('tidbits.daily.results', {}))) {
        await drop(`dailyBoard/${day}/${authUid}`);
      }
      for (const [season, venues] of Object.entries(await leaderboardIndex())) {
        for (const venue of venues) await drop(`standings/${season}/${venue}/${authUid}`);
      }
      // A duel record is SHARED with the opponent — drop only my own slot, never theirs.
      for (const id of readLocal('tidbits.duels', [])) {
        await drop(`duels/${id}/players/${authUid}`);
        await drop(`duelInbox/${authUid}/${id}`);
      }
    }

    try {
      const fresh = await FirebaseNet.deleteAuthUser();
      if (this._profileUnsub) { try { this._profileUnsub(); } catch {} this._profileUnsub = null; }
      this._resetLocalState();
      this.profileId = fresh;
      this.profile = newProfile();
      try { await FirebaseNet.saveProfile(fresh, this.profile); } catch {}
      this._watch(fresh);
      this._save(); this._emit();
      return true;
    } catch (err) {
      this.deleteError = `Couldn't delete your account. ${err?.message || err}`;
      console.error('[Identity] account deletion failed', err);
      return false;
    }
  },

  // Forget everything this device remembers about the deleted account.
  _resetLocalState() {
    this._friends = {};
    for (const k of ['tidbits.friends', 'tidbits.duels', 'tidbits.daily.results', 'tidbits.records',
                     'tidbits.dailyboard.score', 'tidbits.dailyboard.marks', LS_KEY]) {
      try { localStorage.removeItem(k); } catch {}
    }
  },

  // Sign out → back to a fresh anonymous profile on this device. The account's records
  // stay saved in the cloud; signing in again (same provider) restores + merges them.
  async signOut() {
    const uid = await FirebaseNet.signOutUser();
    this.profileId = uid;
    const existing = await FirebaseNet.loadProfile(uid);
    this.profile = existing || newProfile();
    if (!existing) { try { await FirebaseNet.saveProfile(uid, this.profile); } catch {} }
    this._watch(uid);
    this._save(); this._emit();
  },

  _persist() {
    this._save(); this._emit();
    if (this.profileId) FirebaseNet.saveProfile(this.profileId, this.profile).catch(() => {});
  },
  _save() { try { localStorage.setItem(LS_KEY, JSON.stringify(this.profile)); } catch {} },
};

// Account deletion reads the two local registries directly rather than importing Store /
// Duels — duels.js already imports THIS module, so a static import would be a cycle, and
// the registries are the same localStorage keys either way.
function readLocal(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key) || 'null') ?? fallback; } catch { return fallback; }
}

// {season: [venue, ...]} from the static leaderboard the hourly cron commits. A player can
// only have a standing under a venue that appears here, so this is the full search space.
async function leaderboardIndex() {
  try { return await fetch('data/leaderboard/index.json', { cache: 'no-cache' }).then((r) => r.json()) || {}; }
  catch { return {}; }
}

function newProfile() {
  return {
    name: 'Player ' + (1000 + Math.floor(Math.random() * 9000)),
    createdAt: Date.now(),
    avatarSeed: Math.random().toString(36).slice(2, 10),
    rating: { value: 1000, games: 0, provisional: true },
    streak: { current: 0, longest: 0, lastPlayedDay: '', freezes: 0 },
    stats: { gamesPlayed: 0, questionsAnswered: 0, correct: 0, liveNights: 0, venuesVisited: 0 },
  };
}

// Self-correcting bounded Elo (mirror of the Swift/Kotlin updatedRating).
function updatedRating(r, accuracy, weight, field = 1200) {
  const expected = 1 / (1 + Math.pow(10, (field - r.value) / 400));
  const k = (r.provisional ? 64 : 24) * weight;
  const n = r.games + 1;
  const v = Math.max(100, Math.round(r.value + k * (accuracy - expected)));
  return { value: v, games: n, provisional: n < ESTABLISHED_AT };
}

// Cross-context + forgiving streak (mirror of playedStreak).
function playedStreak(s, day, liveNight) {
  let { current, longest, lastPlayedDay, freezes } = s;
  if (day !== lastPlayedDay) {
    const gap = dayGap(lastPlayedDay, day);
    if (!lastPlayedDay || gap === 1) current++;
    else if (gap === 2 && freezes > 0) { freezes--; current++; }
    else current = 1;
    longest = Math.max(longest, current);
    lastPlayedDay = day;
  }
  if (liveNight) freezes = Math.min(freezes + 1, 3);
  return { current, longest, lastPlayedDay, freezes };
}

function isDefaultName(n) { return (n || '').startsWith('Player '); }

// LOSSLESS merge of a local anon profile into an account profile (the survivor) on a
// sign-in conflict — stats summed, order-independent. Mirror of Swift/Kotlin merge.
export function mergeProfiles(local, account) {
  const later = local.streak.lastPlayedDay >= account.streak.lastPlayedDay;
  const rGames = local.rating.games + account.rating.games;
  return {
    name: !isDefaultName(account.name) ? account.name : (!isDefaultName(local.name) ? local.name : account.name),
    createdAt: Math.min(local.createdAt, account.createdAt),
    avatarSeed: account.avatarSeed,
    rating: { value: Math.max(local.rating.value, account.rating.value), games: rGames, provisional: rGames < ESTABLISHED_AT },
    streak: {
      current: later ? local.streak.current : account.streak.current,
      longest: Math.max(local.streak.longest, account.streak.longest),
      lastPlayedDay: later ? local.streak.lastPlayedDay : account.streak.lastPlayedDay,
      freezes: Math.max(local.streak.freezes, account.streak.freezes),
    },
    stats: {
      gamesPlayed: local.stats.gamesPlayed + account.stats.gamesPlayed,
      questionsAnswered: local.stats.questionsAnswered + account.stats.questionsAnswered,
      correct: local.stats.correct + account.stats.correct,
      liveNights: local.stats.liveNights + account.stats.liveNights,
      venuesVisited: Math.max(local.stats.venuesVisited, account.stats.venuesVisited),
    },
  };
}

// Stable, non-reversible profile key from the verified email — Apple + Google with the
// same email land on the SAME profile. Mirror of the Swift/Kotlin sha256Hex(email).
async function accountKey(email) {
  const norm = (email || '').trim().toLowerCase();
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(norm));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Wave E: byte-identical to Swift/Kotlin — calendar-quarter season id + a path-safe venue key.
function currentSeason(d = new Date()) { return `${d.getFullYear()}-S${Math.floor(d.getMonth() / 3) + 1}`; }
function venueKey(v) { return (v || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''); }

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function dayGap(from, to) {
  if (!from) return 1;
  return Math.round((new Date(to + 'T00:00:00') - new Date(from + 'T00:00:00')) / 86400000);
}

// Deterministic avatar hue from the seed — djb2, matching the iOS/Android avatars.
export function avatarHue(seed) {
  let h = 5381;
  for (let i = 0; i < (seed || '').length; i++) h = (h * 33 + seed.charCodeAt(i)) | 0;
  return Math.abs(h) % 360;
}
export function initialsOf(name) {
  const parts = (name || '').trim().split(/\s+/).filter(Boolean).slice(0, 2);
  const s = parts.map((p) => p[0]).join('');
  return s ? s.toUpperCase() : '?';
}
