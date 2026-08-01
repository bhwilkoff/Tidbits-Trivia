// Create-parity — web side. Runs the REAL js/api.js `Corpus.search` against the
// shipped corpus and prints the ids it selects, so they can be diffed against what
// the Apple simulator returned for the same topics (tools/create/parity.sh).
//
// The four engines are unit-tested against the same cases, but until this existed
// nothing compared what they ACTUALLY select for a real topic over the real
// 128k-row corpus — and "the same topic returns the same quiz everywhere" is the
// six-platform contract, not a unit-test property.
//
//   node tools/create/web_search.mjs <api-copy.mjs> <corpus.json> <topics.txt>
//
// `search` is deliberately shuffled at the end (so a quiz does not march
// category-by-category), so this prints a SORTED id set per topic; order is not
// part of the contract, membership is.
import { readFileSync } from 'node:fs';

const [, , apiCopy, corpusPath, topicsPath] = process.argv;
const { Corpus } = await import(apiCopy);

const data = JSON.parse(readFileSync(corpusPath, 'utf8'));
// Mirror of `Corpus.load`'s row mapping without the network/IndexedDB path.
Corpus.questions = data.questions.map((r) => ({
  id: r[0], prompt: r[1], options: r[2], correctIndex: r[3], categoryID: r[4],
  difficulty: r[5], explanation: r[6], sourceTitle: r[7], sourceURL: r[8],
  tags: r[9] || [],
}));
Corpus.loaded = true;

const topics = readFileSync(topicsPath, 'utf8').split('\n')
  .map((t) => t.trim()).filter((t) => t && !t.startsWith('#'));

for (const topic of topics) {
  const ids = Corpus.search(topic, 8).map((q) => q.id).sort();
  console.log(`${topic}\t${ids.join(' ')}`);
}
