// L5 async friend duels — challenge a friend to the SAME question set, answer on your own time,
// higher score wins. Serverless: a duel lives at duels/{id} (create-once + per-player score slots,
// rules-enforced); the challenger drops an invite into the friend's private duelInbox/{uid}.
import { FirebaseNet } from './firebase.js';
import { Identity } from './identity.js';

const LOCAL_KEY = 'tidbits.duels';   // duel ids I'm participating in (no server-side "my duels" query)

export const Duels = {
  _ids: JSON.parse(localStorage.getItem(LOCAL_KEY) || '[]'),
  _track(id) {
    if (this._ids.includes(id)) return;
    this._ids = [id, ...this._ids].slice(0, 40);
    localStorage.setItem(LOCAL_KEY, JSON.stringify(this._ids));
  },

  newId() { return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`; },

  // Challenger creates a duel with a shared question set + invites the friend.
  async challenge(friend, questions) {
    const me = Identity.authUid;
    if (!me || !friend?.uid || !questions?.length) return null;
    const id = this.newId();
    const compact = questions.map((q) => ({ p: q.prompt, o: q.options, c: q.correctIndex, e: q.explanation || '' }));
    await FirebaseNet.createDuel(id, {
      createdBy: me, createdAt: Date.now(), challenged: friend.uid, questions: compact,
      players: { [me]: { name: Identity.profile?.name || 'You', done: false, score: 0 } },
    });
    await FirebaseNet.sendDuelInvite(friend.uid, id, { from: me, fromName: Identity.profile?.name || 'A friend', at: Date.now() });
    this._track(id);
    return id;
  },

  async load(id) { return FirebaseNet.loadDuel(id); },

  // Reconstruct playable questions from a duel's compact set.
  questionsOf(duel) {
    return (duel?.questions || []).map((q, i) => ({
      id: `duel-${i}`, prompt: q.p, options: q.o, correctIndex: q.c, explanation: q.e || '',
      categoryID: 'mixed', difficulty: 3,
    }));
  },

  async submit(id, score) {
    const me = Identity.authUid; if (!me) return;
    await FirebaseNet.submitDuelPlayer(id, me, { name: Identity.profile?.name || 'You', done: true, score });
    this._track(id);
  },

  async inbox() {
    const me = Identity.authUid; if (!me) return [];
    const raw = await FirebaseNet.loadDuelInbox(me);
    return Object.entries(raw || {}).map(([id, v]) => ({ id, ...v })).sort((a, b) => b.at - a.at);
  },

  async accept(id) {
    this._track(id);
    const me = Identity.authUid; if (me) await FirebaseNet.clearDuelInvite(me, id);
  },

  // My active duels — fetch each tracked id + classify (my-turn / waiting / done).
  async mine() {
    const me = Identity.authUid; if (!me) return [];
    const out = [];
    for (const id of this._ids) {
      const d = await FirebaseNet.loadDuel(id);
      if (!d) continue;
      const mine = d.players?.[me];
      const oppUid = Object.keys(d.players || {}).find((u) => u !== me) || d.challenged;
      const opp = oppUid && d.players ? d.players[oppUid] : null;
      out.push({
        id, myDone: !!mine?.done, myScore: mine?.score || 0,
        oppName: opp?.name || 'Opponent', oppDone: !!opp?.done, oppScore: opp?.score || 0,
      });
    }
    return out;
  },
};
