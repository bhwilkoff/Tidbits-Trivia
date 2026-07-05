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

  get signedIn() { return FirebaseNet.isSignedIn(); },
  get email() { return FirebaseNet.currentEmail(); },

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
