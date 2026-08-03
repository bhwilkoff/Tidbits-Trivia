// Web side of the saved-quiz wire goldens. Asserts js/quiz.js decodes the shared
// fixture identically to every other stack, and that a round trip is byte-stable.
//
//   node tools/quiz-wire/check_web.mjs
//
// See tools/quiz-wire/README.md — never edit the fixture to make this pass.
import { readFileSync } from 'node:fs';
import {
  quizFromJSON, quizToJSON, makeQuizID, cleanTitle, resolveQuiz, makeQuiz,
  ID_ALPHABET, bundledSetName,
} from '../../js/quiz.js';

let failures = 0;
function check(label, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.error(`  FAIL ${label}\n    got:  ${JSON.stringify(got)}\n    want: ${JSON.stringify(want)}`); }
  else console.log(`  ok   ${label}`);
}

const path = new URL('./golden/quiz-v1.json', import.meta.url);
const text = readFileSync(path, 'utf8').trim();
const quiz = quizFromJSON(text);

console.log('decode the shared fixture');
check('id', quiz.id, 'k7m3qp9x2r');
check('title', quiz.title, 'Jazz Legends');
check('topic', quiz.topic, 'Jazz');
check('creatorID', quiz.creatorID, 'uid-1');
check('creatorName', quiz.creatorName, 'Ben');
check('createdAt', quiz.createdAt, 1753900000000);
check('mode', quiz.mode, 'mix');
check('entry count', quiz.entries.length, 3);
check('entry 0 is a ref', quiz.entries[0], 'src:desc:Q1');
check('entry 1 is inline', Array.isArray(quiz.entries[1]), true);
check('entry 2 is a SET ref', quiz.entries[2], { i: 'src:describe:Ornette_Coleman', s: 'picture' });

console.log('re-encode is byte-identical (sorted keys, no drift)');
check('round trip', quizToJSON(quiz), text);

console.log('resolution degrades honestly');
const r = resolveQuiz(quiz, (id) => (id === 'src:desc:Q1' ? { id, prompt: 'p' } : null));
check('resolved count', r.questions.length, 2);      // the ref + the inline
check('missing count', r.missing, 1);                // the set ref is unresolvable
check('not complete', r.isComplete, false);
check('inline survived without a corpus', r.questions[1].prompt,
      'Which Texan city did the group form in?');

const none = resolveQuiz(quiz, () => null);
check('below the floor is not playable', none.isPlayable, false);

console.log('a set ref never falls back to the colliding corpus row');
// The corpus holds a DIFFERENT question under this exact id -- serving it would be
// the silent substitution the contract forbids.
// Entry 0 IS a corpus ref, so it legitimately resolves; only the SET ref must not.
const collide = resolveQuiz(quiz,
  () => ({ id: 'x', prompt: 'THE WRONG TEXT QUESTION' }),
  () => null);
check('set ref left missing, not filled from the corpus', collide.missing, 1);
check('only the corpus ref + inline resolved', collide.questions.length, 2);
const viaSet = resolveQuiz(quiz, () => null,
  (set, id) => (set === 'picture' ? { id, prompt: 'Who is this?', image: 'x.jpg' } : null));
check('set ref resolves from its own set', viaSet.questions.some((q) => q.prompt === 'Who is this?'), true);

console.log('a payload-less shape owns EVERY prefix its generators emit');
// `oddrel:` is 590 of the 1,094 shipped Odd-one-out rows and `biztot:` is every
// business pair. Matching only `odd:` / `tot:` made them plain corpus refs, which
// resolve against a corpus that does not hold them -- the question just vanished.
check('tot', bundledSetName({ id: 'tot:first:A|B' }), 'thisorthat');
check('biztot', bundledSetName({ id: 'biztot:3M|AMD' }), 'thisorthat');
check('odd', bundledSetName({ id: 'odd:geo:1' }), 'oddoneout');
check('oddrel', bundledSetName({ id: 'oddrel:P170:12' }), 'oddoneout');
check('a longer word starting the same way is not that set',
      bundledSetName({ id: 'total:recall:1' }), null);

console.log('ids and titles');
let seed = 42;
const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const ids = Array.from({ length: 300 }, () => makeQuizID(rand));
check('id length', ids.every((i) => i.length === 10), true);
check('id alphabet', ids.every((i) => [...i].every((c) => ID_ALPHABET.includes(c))), true);
check('no ambiguous chars', ids.some((i) => /[01loiu]/.test(i)), false);
check('ids are unique', new Set(ids).size, ids.length);
check('title trimmed', cleanTitle('  Jazz  '), 'Jazz');
check('empty title falls back', cleanTitle('   '), 'Untitled quiz');
check('long title capped', cleanTitle('x'.repeat(200)).length, 60);

console.log('lenient decoding — these objects outlive the app that wrote them');
const withUnknown = quizFromJSON(JSON.stringify({ ...JSON.parse(text), fromV2: { a: 1 } }));
check('unknown keys ignored', withUnknown.entries.length, 3);
const withJunk = quizFromJSON(JSON.stringify({ ...JSON.parse(text), qs: ['src:a', 42, ['short'], { s: 'picture' }, 'pic:b'] }));
check('malformed entries skipped', withJunk.entries.length, 2);
check('no id is rejected', quizFromJSON('{"by":"u","qs":[]}'), null);

console.log('a ref-only quiz stays small enough to sync and share');
const big = makeQuiz({
  questions: Array.from({ length: 20 }, (_, i) => ({ id: `src:desc:Q${i}`, templateID: 'src' })),
  topic: 'Space', creatorID: 'uid-1', creatorName: 'Ben', id: 'aaaaaaaaaa', createdAt: 0,
});
check('20 refs under 1KB', quizToJSON(big).length < 1024, true);

if (failures) { console.error(`\n${failures} FAILED`); process.exit(1); }
console.log('\nall web quiz-wire goldens passed');
