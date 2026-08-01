// Verify the web mirror agrees with Swift on the drift rules, by executing the
// REAL js/api.js relevance functions against the shipped corpus.
import fs from 'node:fs';
const src = fs.readFileSync('js/api.js', 'utf8');
// Lift the pure relevance helpers out of the module (they are file-scoped, not
// exported) by evaluating just their definitions.
const names = ['fold', 'isWordChar', 'containsWord', 'stripParens', 'flattened',
               'topicPhrase', 'topicTokens', 'hasAgentiveTag', 'tierOf', 'STOPWORDS', '_foldCache'];
const start = src.indexOf('const _foldCache');
const end = src.indexOf('function fillByTier');
const block = src.slice(start, end);
const mod = new Function(block + '\nreturn {' + names.filter(n => block.includes(n)).join(',') + '};')();
const { containsWord, topicPhrase, topicTokens, tierOf } = mod;

let fails = 0;
const ok = (cond, label) => { if (!cond) { console.log('FAIL', label); fails++; } };

ok(containsWord('art deco', 'art'), 'art deco');
ok(!containsWord('mozart', 'art'), 'mozart');
ok(!containsWord('hansel and gretel', 'ansel'), 'hansel');
ok(!containsWord('spokane washington', 'kane'), 'spokane');
ok(!containsWord('indianapolis', 'india'), 'indianapolis');

const tier = (title, { prompt = '', tags = [], topic, guard = false } = {}) =>
  tierOf(title, prompt, tags, topicTokens(topic), topicPhrase(topic), guard);

ok(tier('Spokane, Washington', { topic: 'Harry Kane' }) === null, 'harry kane spokane');
ok(tier('Butane', { topic: 'Harry Kane' }) === null, 'harry kane butane');
ok(tier('Bob Denver', { topic: 'Denver', guard: true }) === null, 'bob denver');
ok(tier('Denver Pyle', { topic: 'Denver', guard: true }) === null, 'denver pyle');
ok(tier('Denver International Airport', { topic: 'Denver', guard: true }) !== null, 'denver airport');
ok(tier('Harry Potter', { topic: 'Potter' }) !== null, 'potter unguarded');
ok(tier('Thriller (album)', { tags: ['Albums produced by Michael Jackson'], topic: 'Michael Jackson' }) !== null, 'mj tag');
ok(tier('Kristin Cavallari', { tags: ['Actresses from Denver'], topic: 'Denver' }) === null, 'denver from-tag');
ok(tier('Neil Sedaka', { tags: ['Abraham Lincoln High School (Brooklyn) alumni'], topic: 'Abraham Lincoln' }) === null, 'lincoln school');
ok(topicPhrase('Masters of the Universe (2026 film)') === 'masters of the universe', 'disambiguator');
ok(!topicTokens('Backrooms (film)').includes('film'), 'no film token');
ok(topicPhrase('World War II') === 'world war ii', 'phrase keeps stopwords');
ok(tier('Denver', { topic: 'Denver' }) === 3, 'denver tier3');
ok(tier('Denver International Airport', { topic: 'Denver' }) === 2, 'airport tier2');
const byTag = tier('Bad (album)', { tags: ['Albums produced by Michael Jackson'], topic: 'Michael Jackson' });
const byTitle = tier('Dangerous (Michael Jackson album)', { topic: 'Michael Jackson' });
ok(byTag < byTitle, 'tag ranks below title');

console.log(fails === 0 ? `web mirror OK (${19 - fails}/19)` : `${fails} FAILURES`);
process.exit(fails ? 1 : 0);
