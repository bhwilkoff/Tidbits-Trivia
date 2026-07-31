// The tidbits.savedSets -> quiz.v1 migration decision (docs/QUIZ-CONTRACT.md §7).
//
// This tests the PURE part -- which entry shape each legacy question becomes -- by
// importing the real `legacyEntry`. An earlier version of this file re-implemented
// the whole migration against a stubbed corpus and PASSED while the shipping code
// inlined every question, because the stub hid the fact that the migration ran
// before the corpus finished loading. The ordering half is checked in a real
// browser instead; a stub cannot tell you when something is ready.
import { legacyEntry } from '../../js/quizstore.js';

let failures = 0;
function check(label, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) { failures++; console.error(`  FAIL ${label}\n    got:  ${JSON.stringify(got)}\n    want: ${JSON.stringify(want)}`); }
  else console.log(`  ok   ${label}`);
}

const q = (id) => ({ id, prompt: 'p', options: ['a', 'b', 'c', 'd'], correctIndex: 1,
                     categoryID: 'arts', difficulty: 3, explanation: 'e',
                     sourceTitle: 't', sourceURL: '' });

console.log('each legacy question becomes the RIGHT entry shape');
const lookup = (id) => {
  if (id === 'src:cloze:Himyar') return q(id);                         // corpus hit
  if (id === 'src:describe:Sayfo') return { question: q(id), set: 'picture' };
  return null;
};
check('corpus question -> bare ref', legacyEntry(q('src:cloze:Himyar'), lookup), 'src:cloze:Himyar');
check('bundled question -> set ref', legacyEntry(q('src:describe:Sayfo'), lookup),
      { i: 'src:describe:Sayfo', s: 'picture' });
const inline = legacyEntry(q('genuinely:retired'), lookup);
check('unresolvable -> inline row', Array.isArray(inline), true);

console.log('an inlined question keeps its ORIGINAL id');
// Rewriting it (an earlier version prefixed `live:`) destroys the only information
// a later pass could use to turn it back into a ref.
check('id preserved verbatim', inline[0], 'genuinely:retired');

console.log('a missing corpus must NOT be mistaken for a retired question');
// This is the shape of the bug the browser found: with nothing resolvable, EVERY
// question inlines. The decision is correct in isolation -- which is exactly why
// the ordering has to be guaranteed by the caller, not by this function.
const blind = legacyEntry(q('src:cloze:Himyar'), () => null);
check('inlines when the lookup is blind', Array.isArray(blind), true);
check('and still keeps the id, so it is recoverable', blind[0], 'src:cloze:Himyar');

console.log('degenerate rows survive');
check('missing fields get defaults', legacyEntry({ id: 'x' }, () => null).length, 9);
check('no id at all', legacyEntry({}, () => null)[0], '');

if (failures) { console.error(`\n${failures} FAILED`); process.exit(1); }
console.log('\nall migration-decision checks passed');
