// Verify the web mirror agrees with Swift on the drift rules, by executing the
// REAL js/api.js relevance functions against the shipped corpus.
import fs from 'node:fs';
const src = fs.readFileSync('js/api.js', 'utf8');
// Lift the pure relevance helpers out of the module (they are file-scoped, not
// exported) by evaluating just their definitions.
const names = ['fold', 'isWordChar', 'containsWord', 'stripParens', 'flattened',
               'topicPhrase', 'phraseIsRequired', 'topicTokens', 'hasAgentiveTag',
               'promptHasWord', 'tierOf', 'STOPWORDS', '_foldCache'];
const start = src.indexOf('const _foldCache');
const end = src.indexOf('function fillByTier');
const block = src.slice(start, end);
const mod = new Function(block + '\nreturn {' + names.filter(n => block.includes(n)).join(',') + '};')();
const { containsWord, topicPhrase, topicTokens, tierOf, phraseIsRequired, promptHasWord } = mod;

let fails = 0;
const ok = (cond, label) => { if (!cond) { console.log('FAIL', label); fails++; } };

ok(containsWord('art deco', 'art'), 'art deco');
ok(!containsWord('mozart', 'art'), 'mozart');
ok(!containsWord('hansel and gretel', 'ansel'), 'hansel');
ok(!containsWord('spokane washington', 'kane'), 'spokane');
ok(!containsWord('indianapolis', 'india'), 'indianapolis');

const tier = (title, { prompt = '', tags = [], topic, guard = false } = {}) =>
  tierOf(title, prompt, tags, topicTokens(topic), topicPhrase(topic), guard,
         phraseIsRequired(topic));

ok(tier('Spokane, Washington', { topic: 'Harry Kane' }) === null, 'harry kane spokane');
ok(tier('Butane', { topic: 'Harry Kane' }) === null, 'harry kane butane');
ok(tier('Bob Denver', { topic: 'Denver', guard: true }) === null, 'bob denver');
ok(tier('Denver Pyle', { topic: 'Denver', guard: true }) === null, 'denver pyle');
ok(tier('Denver International Airport', { topic: 'Denver', guard: true }) !== null, 'denver airport');
ok(tier('Harry Potter', { topic: 'Potter' }) !== null, 'potter unguarded');
ok(tier('Thriller (album)', { tags: ['Albums produced by Michael Jackson'], topic: 'Michael Jackson' }) === null, 'tag alone no longer admits');
ok(tier('Kristin Cavallari', { tags: ['Actresses from Denver'], topic: 'Denver' }) === null, 'denver from-tag');
ok(tier('Neil Sedaka', { tags: ['Abraham Lincoln High School (Brooklyn) alumni'], topic: 'Abraham Lincoln' }) === null, 'lincoln school');
ok(topicPhrase('Masters of the Universe (2026 film)') === 'masters of the universe', 'disambiguator');
ok(!topicTokens('Backrooms (film)').includes('film'), 'no film token');
ok(topicPhrase('World War II') === 'world war ii', 'phrase keeps stopwords');
ok(tier('Denver', { topic: 'Denver' }) === 3, 'denver tier3');
ok(tier('Denver International Airport', { topic: 'Denver' }) === 2, 'airport tier2');
ok(tier('Britt Ekland', { tags: ['Partners of Rod Stewart'], topic: 'Rod Stewart' }) === null,
   'partners-of tag rejected');
ok(tier('Bad (album)', { topic: 'Michael Jackson', prompt: "Michael Jackson's seventh studio album" }) === 0,
   'same row survives when the prompt names him');

// A regnal numeral is short but not insignificant — "George VI" reduced to the
// single token `george` and returned George Martin, George Eliot and Paul George.
ok(phraseIsRequired('George VI'), 'george vi requires phrase');
ok(phraseIsRequired('O. J. Simpson'), 'oj requires phrase');
ok(tier('George Martin', { topic: 'George VI' }) === null, 'george martin rejected');
ok(tier('Paul George', { topic: 'George VI' }) === null, 'paul george rejected');
ok(tier('Homer Simpson', { topic: 'O. J. Simpson' }) === null, 'homer rejected');
ok(tier('George VI', { topic: 'George VI' }) === 3, 'george vi tier3');
// ...and it must NOT fire when the dropped word is a mere stopword.
ok(!phraseIsRequired('The Beatles'), 'beatles no phrase requirement');
ok(!phraseIsRequired('Denver'), 'denver no phrase requirement');
ok(tier('Abbey Road', { topic: 'The Beatles', prompt: 'the beatles recorded it here' }) !== null,
   'abbey road still admitted');

// Identity ignores the disambiguator: the corpus titles the rapper "Drake
// (musician)", so the guard never armed and "Drake" returned Nick Drake.
ok(tier('Drake (musician)', { topic: 'Drake' }) === 3, 'drake musician is drake');
ok(tier('Nick Drake', { topic: 'Drake', guard: true }) === null, 'nick drake rejected');
ok(tier('Drake & Josh', { topic: 'Drake', guard: true }) === null, 'drake and josh rejected');
// ...while CONTAINMENT still reads the full title.
ok(tier('Dangerous (Michael Jackson album)', { topic: 'Michael Jackson' }) === 2,
   'containment sees the disambiguator');

// A prompt occurrence inside a DIFFERENT proper name is not a match. "Denver"
// matched "...and John Denver"; "Michael Jackson" matched a Glenda Jackson biopic.
const T = (t) => topicTokens(t);
ok(!promptHasWord('Written by Bill Danoff and John Denver', 'denver', T('Denver')),
   'john denver rejected in prose');
ok(promptHasWord('before Denver drafted him in 2024', 'denver', T('Denver')),
   'plain denver accepted');
ok(promptHasWord('this Denver-based budget carrier', 'denver', T('Denver')),
   'hyphenated denver accepted');
ok(!promptHasWord("marked Glenda Jackson's final role", 'jackson', T('Michael Jackson')),
   'glenda jackson rejected');
ok(promptHasWord("Michael Jackson's seventh studio album", 'jackson', T('Michael Jackson')),
   'possessive of the topic accepted');
// ...and the second half of the rule: a capitalised predecessor the player TYPED.
ok(promptHasWord('Written by John Lennon and Paul McCartney', 'mccartney', T('Paul McCartney')),
   'paul mccartney still matches');

console.log(fails === 0 ? 'web mirror OK (38/38)' : `${fails} FAILURES`);
process.exit(fails ? 1 : 0);
