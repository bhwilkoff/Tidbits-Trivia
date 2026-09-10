// The wrap's bookkeeping, pure (no DOM, no Firebase) so it can be tested with
// node alone. Mirrors Swift LiveRecapBook: one entry per revealed question, the
// score before it was asked and after it was scored; "nailed" is decided by the
// SCORE — the host is the scorer, and a typed answer accepted by hand counts.
export function newRecap() { return { entries: [], openQid: null, scoreAtQuestion: 0 }; }

function close(book, score) {
  const e = book.entries.find((x) => x.qid === book.openQid && x.after == null);
  if (e) e.after = score;
}

/** A pub arrived; `score` is the joiner's score right now. */
export function observe(book, p, score) {
  if (!p) return book;
  if (p.qid !== book.openQid) { close(book, score); book.openQid = p.qid; book.scoreAtQuestion = score; }
  if (p.phase === 'reveal' && !book.entries.some((x) => x.qid === p.qid)) {
    book.entries.push({ qid: p.qid, prompt: p.prompt || '', answer: p.answer || null, difficulty: p.difficulty || null,
      story: p.story || null, sourceTitle: p.source?.title || null, sourceURL: p.source?.url || null,
      before: book.scoreAtQuestion, after: null });
  }
  return book;
}

/** The night ended, or a score landed at the wrap: settle the last question. */
export function finish(book, score) {
  close(book, score);
  const last = book.entries[book.entries.length - 1];
  if (last) last.after = Math.max(last.after ?? score, score);   // a late score write belongs to the last question
  return book;
}

export const nailed = (e) => (e.after ?? e.before) > e.before;
export const tough = (book) => book.entries.filter((e) => nailed(e) && (e.difficulty || 0) >= 4);
export const toRemember = (book) => book.entries.filter((e) => !nailed(e) && e.answer);
export const howDidYouKnowText = (e) => `I knew "${e.prompt}" at trivia night — it's ${e.answer}. How did YOU know that? 🧠`;
