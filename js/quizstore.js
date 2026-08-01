// Local persistence for saved quizzes on the web (docs/QUIZ-CONTRACT.md §4).
//
// Local is the source of truth for a player's own quizzes: they must work offline
// and before sign-in, so nothing here needs an account. Sync and sharing layer on
// top. What's stored is the CONTRACT JSON, not a web-specific shape — otherwise
// there'd be a fifth representation to keep in step with the four stacks.

import { Corpus, Pictures, ThisOrThat, ClosestCall, Ordering, Matching, TypeAnswer, OddOneOut, Enumerate } from './api.js';
import { quizToJSON, quizFromJSON, quizToWire, quizFromWire, makeQuiz, cleanTitle, resolveQuiz } from './quiz.js';
import { FirebaseNet } from './firebase.js';

const KEY = 'tidbits.quizzes';
const LEGACY_KEY = 'tidbits.savedSets';

// The bundled sets by their contract name. A set-ref names its set precisely
// because a bare ID would be ambiguous — these share the corpus `src:` namespace.
const SETS = {
  picture: Pictures, thisorthat: ThisOrThat, closest: ClosestCall, order: Ordering,
  match: Matching, typeanswer: TypeAnswer, oddoneout: OddOneOut, enumerate: Enumerate,
};

function readAll() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || '[]');
    return raw.map(quizFromJSON).filter(Boolean);
  } catch { return []; }
}

function writeAll(quizzes) {
  localStorage.setItem(KEY, JSON.stringify(quizzes.map(quizToJSON)));
}

/** Newest first — a quiz you just made belongs at the top of your list. */
export function allQuizzes() {
  return readAll().sort((a, b) => b.createdAt - a.createdAt);
}

export function getQuiz(id) {
  return readAll().find((q) => q.id === id) || null;
}

/** Idempotent: saving the same quiz twice updates it rather than duplicating. */
export function saveQuiz(quiz) {
  const list = readAll().filter((q) => q.id !== quiz.id);
  list.unshift(quiz);
  writeAll(list);
  return quiz;
}

export function deleteQuiz(id) {
  writeAll(readAll().filter((q) => q.id !== id));
}

export function renameQuiz(id, title) {
  const list = readAll();
  const q = list.find((x) => x.id === id);
  if (!q) return;
  q.title = cleanTitle(title);
  writeAll(list);
}

/** Build and store in one step — every created quiz is kept automatically. */
export function saveCreated({ questions, topic, creatorID, creatorName, mode = 'mix' }) {
  return saveQuiz(makeQuiz({ questions, topic, creatorID, creatorName, mode }));
}

/**
 * Resolve a quiz's refs against everything this build actually ships. Ordering is
 * preserved and an unresolvable ref is COUNTED, not replaced — a shared quiz that
 * quietly swaps in a different question is worse than one that admits it is short.
 */
export function resolveForPlay(quiz) {
  return resolveQuiz(
    quiz,
    (id) => Corpus.question(id),
    // Deliberately no corpus fallback: the corpus holds a DIFFERENT question under
    // a bundled set's ID (166 of 200 sampled Picture ID rows collide), which is the
    // whole reason set-refs carry their set.
    (set, id) => SETS[set]?.question(id) || null,
  );
}

/**
 * One legacy question -> one contract entry. PURE and exported so the migration's
 * actual decision is testable: a stubbed-corpus test of the whole migration passed
 * while the real thing inlined everything, because the stub hid an ordering bug.
 * Test this, and check the ordering in a real browser.
 */
export function legacyEntry(q, lookup) {
  const hit = lookup(q.id);
  if (hit && hit.set) return { i: q.id, s: hit.set };          // bundled-set ref
  if (hit) return q.id;                                        // corpus ref
  // Genuinely unresolvable: inline it, keeping the ORIGINAL id. Rewriting the id
  // would destroy the only thing a later pass could use to re-reference it.
  return [q.id || '', q.prompt || '', q.options || ['', '', '', ''],
          q.correctIndex || 0, q.categoryID || 'mixed', q.difficulty || 3,
          q.explanation || '', q.sourceTitle || '', q.sourceURL || ''];
}

/** The canonical link target for a quiz on every platform (QUIZ-CONTRACT §5). */
export function quizShareURL(id) {
  return `${location.origin}${location.pathname.replace(/index\.html$/, '')}#/quiz/${id}`;
}

/**
 * Publish so anyone with the link can play it. EXPLICIT — a quiz you never share
 * never leaves your account. The creator is stamped at publish time so the rules
 * (`by === auth.uid`) allow only its author to overwrite it later.
 */
export async function publishQuiz(quiz) {
  const uid = await FirebaseNet.ensureUid();
  const wire = quizToWire({ ...quiz, creatorID: uid || quiz.creatorID || 'local' });
  await FirebaseNet.publishQuiz(quiz.id, wire);
  // Remember locally that it is out there, so the UI can say "Shared" without a
  // network round trip.
  const list = readAll();
  const mine = list.find((q) => q.id === quiz.id);
  if (mine) { mine.creatorID = wire.by; writeAll(list); }
  return quizShareURL(quiz.id);
}

/**
 * Fetch a shared quiz by id.
 *
 * Returns `{ quiz }` on success, `{ notFound: true }` when the id really isn't
 * there, and `{ error }` when the lookup FAILED. Collapsing the last two into null
 * told someone with a working link that their friend had deleted the quiz, when the
 * truth was a network blip or a stale cached module -- a wrong explanation is worse
 * than an honest "couldn't load", because it stops them retrying.
 */
export async function fetchSharedQuiz(id) {
  try {
    const wire = await FirebaseNet.loadQuiz(id);
    if (!wire) return { notFound: true };
    const quiz = quizFromWire(wire);
    return quiz ? { quiz } : { error: 'This quiz is in a format this version can\u2019t read.' };
  } catch (e) {
    console.warn('[Tidbits] shared quiz lookup failed', e);
    return { error: 'Couldn\u2019t reach the quiz. Check your connection and try again.' };
  }
}

/** Keep a shared quiz you were given, so it joins your own shelf. */
export function keepSharedQuiz(quiz) {
  if (getQuiz(quiz.id)) return quiz;      // already yours
  return saveQuiz(quiz);
}

/** Where a legacy question's ID still resolves today. */
function lookupAnywhere(id) {
  if (!id) return null;
  const fromCorpus = Corpus.question(id);
  if (fromCorpus) return fromCorpus;
  for (const set of Object.keys(SETS)) {
    const q = SETS[set].question(id);
    if (q) return { question: q, set };
  }
  return null;
}

/**
 * One-time migration off the pre-contract `tidbits.savedSets` format, which stored
 * FULL question text keyed by a label, was web-only, and could not be shared.
 *
 * ASYNC, and it awaits the corpus on purpose. Running it before the corpus finished
 * loading made every lookup miss, so every question was inlined -- turning a
 * 400-byte quiz into a 40KB one, the exact failure QUIZ-CONTRACT §7 warns about.
 * A headless test hid this by stubbing the corpus as always-loaded; only running it
 * in a real browser showed it.
 *
 * A question that genuinely no longer resolves is inlined with its ORIGINAL id
 * intact. Rewriting it (an earlier version prefixed `live:`) would have destroyed
 * the only information a later pass could use to re-reference it.
 *
 * The legacy key is deleted only AFTER the converted list is written, so an
 * interrupted migration cannot lose the player's quizzes.
 */
export async function migrateLegacySavedSets() {
  let legacy;
  try { legacy = JSON.parse(localStorage.getItem(LEGACY_KEY) || 'null'); } catch { legacy = null; }
  if (!Array.isArray(legacy) || !legacy.length) return 0;

  // Without this the migration silently degrades to "inline everything".
  try { await Corpus.load(); } catch { /* fall through: inlining is the honest fallback */ }
  await Promise.all(Object.values(SETS).map((s) => s.load?.().catch(() => {})));

  const existing = readAll();
  const seenTitles = new Set(existing.map((q) => q.title.toLowerCase()));
  const converted = [];
  for (const set of legacy) {
    if (!set || !Array.isArray(set.questions) || !set.questions.length) continue;
    const label = cleanTitle(set.label || '');
    if (seenTitles.has(label.toLowerCase())) continue;   // already migrated
    // Entries are built directly rather than through makeQuiz, whose ref-vs-inline
    // heuristic keys off a `live:` id -- which is why the earlier version had to
    // mangle ids to force inlining.
    const entries = set.questions.map((q) => legacyEntry(q, lookupAnywhere));
    converted.push({
      id: makeQuiz({ questions: [], topic: '', creatorID: 'local' }).id,
      title: label,
      topic: set.label || '',
      creatorID: 'local',
      creatorName: '',
      createdAt: typeof set.savedAt === 'number' ? set.savedAt : Date.now(),
      mode: 'mix',
      entries,
    });
    seenTitles.add(label.toLowerCase());
  }

  if (converted.length) writeAll([...converted, ...existing]);
  localStorage.removeItem(LEGACY_KEY);          // only after the write succeeded
  return converted.length;
}
