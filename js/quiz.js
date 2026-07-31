// Saved quizzes — the first user-authored object in Tidbits, so it is a wire
// contract before it is a screen (docs/QUIZ-CONTRACT.md).
//
// A quiz stores question REFERENCES, not question text: every platform already
// ships the corpus, so a 20-question quiz is under 1KB and costs nothing to sync,
// host, or put in a URL. Only live-generated questions (always plain MCQ, because
// the corpus was thin on that topic) travel inline, in the exact corpus.json row
// shape this file already decodes elsewhere.
//
// Mirrors Swift SavedQuiz.swift, Kotlin SavedQuiz.kt and C# SavedQuiz.cs; pinned by
// tools/quiz-wire/golden/quiz-v1.json.

// Crockford-style, with 0/o, 1/l/i and u removed so an ID read aloud in a pub or
// typed off a projector is unambiguous, and a random ID can't spell something
// unfortunate. 30 chars: 30^10 ~= 5.9e14.
export const ID_ALPHABET = '23456789abcdefghjkmnpqrstvwxyz';
export const ID_LENGTH = 10;

// Below this a quiz isn't worth playing; above it we play and say so.
export const MINIMUM_PLAYABLE = 3;

// Random, never derived from content: two people who both make a "Jazz" quiz must
// get different IDs, and an ID must not leak what is inside it. `rand` is injectable
// so the codec can be tested deterministically.
export function makeQuizID(rand = Math.random) {
  let out = '';
  for (let i = 0; i < ID_LENGTH; i++) out += ID_ALPHABET[Math.floor(rand() * ID_ALPHABET.length)];
  return out;
}

// Titles ride in share cards and list rows, so they are trimmed and capped rather
// than rejected — a long paste should still save.
export function cleanTitle(raw) {
  const t = (raw || '').trim();
  const fallback = t || 'Untitled quiz';
  return fallback.length <= 60 ? fallback : fallback.slice(0, 60);
}

// Live Wikipedia generation is the only source that isn't addressable by ID from a
// bundled file, so it is the only thing a quiz has to carry inline.
function isLiveGenerated(q) {
  return (q.id || '').startsWith('live:') || q.templateID === 'live';
}

function inlineRow(q) {
  return [q.id, q.prompt, q.options, q.correctIndex, q.categoryID,
          q.difficulty, q.explanation, q.sourceTitle, q.sourceURL || ''];
}

function questionFromRow(r) {
  return {
    id: r[0], prompt: r[1], options: r[2], correctIndex: r[3], categoryID: r[4],
    difficulty: r[5], explanation: r[6], sourceTitle: r[7], sourceURL: r[8] || '',
    templateID: (r[0] || '').split(':')[0] || 'live',
  };
}

function isValidRow(r) {
  return Array.isArray(r) && r.length >= 9
    && typeof r[0] === 'string' && typeof r[1] === 'string'
    && Array.isArray(r[2]) && r[2].length === 4
    && typeof r[3] === 'number' && typeof r[4] === 'string'
    && typeof r[5] === 'number' && typeof r[6] === 'string'
    && typeof r[7] === 'string';
}

// Build from a played/generated set. Questions already in a bundled source become
// refs; anything else (a live Wikipedia MCQ) is inlined.
export function makeQuiz({ questions, topic, title, mode = 'mix', creatorID, creatorName,
                           id, createdAt = Date.now() }) {
  return {
    id: id || makeQuizID(),
    title: cleanTitle(title || topic),
    topic: topic || '',
    creatorID,
    creatorName: creatorName || '',
    createdAt,
    mode,
    entries: questions.map((q) => (isLiveGenerated(q) ? inlineRow(q) : q.id)),
  };
}

// Terse keys because this object rides in share URLs and RTDB. Renaming one is a
// breaking change; readers must ignore keys they don't know.
export function quizToWire(quiz) {
  return {
    v: 1,
    id: quiz.id,
    t: quiz.title,
    tp: quiz.topic,
    by: quiz.creatorID,
    bn: quiz.creatorName,
    at: quiz.createdAt,
    m: quiz.mode,
    qs: quiz.entries,
  };
}

// Lenient by contract: unknown keys are ignored and a malformed entry is skipped
// rather than failing the whole quiz, because these objects outlive the app version
// that wrote them.
export function quizFromWire(w) {
  if (!w || typeof w !== 'object') return null;
  if (typeof w.id !== 'string' || !w.id) return null;
  if (typeof w.by !== 'string') return null;
  if (!Array.isArray(w.qs)) return null;
  const entries = [];
  for (const raw of w.qs) {
    if (typeof raw === 'string' && raw) entries.push(raw);
    else if (isValidRow(raw)) entries.push(raw);
  }
  return {
    id: w.id,
    title: cleanTitle(typeof w.t === 'string' ? w.t : ''),
    topic: typeof w.tp === 'string' ? w.tp : '',
    creatorID: w.by,
    creatorName: typeof w.bn === 'string' ? w.bn : '',
    createdAt: typeof w.at === 'number' ? w.at : 0,
    mode: typeof w.m === 'string' ? w.m : 'mix',
    entries,
  };
}

// Sorted keys so two devices writing the same quiz produce byte-identical output —
// that is what makes the merge guard in QUIZ-CONTRACT §4 ("created or deleted, never
// edited in place") checkable rather than aspirational.
export function quizToJSON(quiz) {
  const w = quizToWire(quiz);
  return JSON.stringify(w, Object.keys(w).sort());
}

export function quizFromJSON(text) {
  try { return quizFromWire(JSON.parse(text)); } catch { return null; }
}

// Resolve refs in order against the local corpus. `lookup` returns null/undefined for
// an ID this build can't resolve. Never substitutes a different question — a shared
// quiz that quietly changes content is worse than one that admits it is incomplete.
export function resolveQuiz(quiz, lookup) {
  const questions = [];
  let missing = 0;
  for (const entry of quiz.entries) {
    if (typeof entry === 'string') {
      const q = lookup(entry);
      if (q) questions.push(q); else missing++;
    } else {
      questions.push(questionFromRow(entry));
    }
  }
  return {
    questions,
    missing,
    isPlayable: questions.length >= MINIMUM_PLAYABLE,
    isComplete: missing === 0,
  };
}
