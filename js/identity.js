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
  async bootstrap() {
    try { const c = JSON.parse(localStorage.getItem(LS_KEY) || 'null'); if (c) { this.profile = c; this._emit(); } } catch {}
    try {
      const uid = await FirebaseNet.ensureUid();
      this.profileId = uid;
      const remote = await FirebaseNet.loadProfile(uid);
      this.profile = remote || this.profile || newProfile();
      if (!remote) { try { await FirebaseNet.saveProfile(uid, this.profile); } catch {} }
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

  rename(name) {
    if (!this.profile) return;
    const t = (name || '').trim().slice(0, 24); if (!t) return;
    this.profile.name = t; this._persist();
  },

  get signedIn() { return FirebaseNet.isSignedIn(); },
  get email() { return FirebaseNet.currentEmail(); },

  // Promote the anon account (Apple/Google) so records roam + survive session loss.
  // On a conflict (the credential already has an account), merge losslessly into it.
  async signIn(providerId) {
    const localProfile = this.profile || {};
    const res = await FirebaseNet.signInWith(providerId);
    this.profileId = res.uid;
    if (res.merged) {
      const account = (await FirebaseNet.loadProfile(res.uid)) || newProfile();
      this.profile = mergeProfiles(localProfile, account);
      await FirebaseNet.saveProfile(res.uid, this.profile);
      if (res.prevUid && res.prevUid !== res.uid) FirebaseNet.deleteProfile(res.prevUid);
    } else if (this.profile) {
      await FirebaseNet.saveProfile(res.uid, this.profile);   // promoted in place; keep records
    }
    this._save(); this._emit();
    return res.merged;
  },

  // Sign out → back to a fresh anonymous profile on this device. The account's records
  // stay saved in the cloud; signing in again (same provider) restores + merges them.
  async signOut() {
    const uid = await FirebaseNet.signOutUser();
    this.profileId = uid;
    const existing = await FirebaseNet.loadProfile(uid);
    this.profile = existing || newProfile();
    if (!existing) { try { await FirebaseNet.saveProfile(uid, this.profile); } catch {} }
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
