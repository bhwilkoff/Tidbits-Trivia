// Daily-parity golden — web side (Decision 037). Imports the REAL js/engine.js
// pickDaily (via a byte-identical .mjs copy made by run.sh — the repo has no
// package.json, so node would parse the .js as CommonJS) and the web corpus
// asset. Writes "<day> <id1> … <id7>" per test day for run.sh to diff.
import { readFileSync, writeFileSync } from 'node:fs';

const DAYS = ['2026-07-01', '2026-07-02', '2026-12-31', '2027-02-28'];

const [, , engineCopy, corpusPath, outPath] = process.argv;
const { pickDaily } = await import(engineCopy);

const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
const ids = corpus.questions.map((q) => q[0]); // compact rows: index 0 = id
if (ids.length < 100) { console.error(`FAIL: only ${ids.length} ids`); process.exit(1); }

let out = '';
for (const day of DAYS) {
  out += `${day} ${pickDaily(ids, day, 'mixed', 7).join(' ')}\n`;
}
writeFileSync(outPath, out);
console.log(`web: ${DAYS.length} days written`);
