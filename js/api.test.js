/**
 * Vanilla test harness — no framework, no build step.
 *
 * Run in a browser:
 *   1. python3 -m http.server 8080
 *   2. open http://localhost:8080/js/api.test.html
 *      (or load this file from a <script> tag in an HTML page)
 * Run in node 22+:
 *   node js/api.test.js
 *
 * Pattern: every `test(...)` runs synchronously or as a Promise; results
 * print to console + (in the browser) the page. Add more tests as the
 * api.js surface grows. Mirrors the iOS Swift Testing + Android JUnit
 * + Turbine pattern — same shape, native tools.
 */

// Node fallback: api.js is a browser IIFE that attaches `API` to its
// closure. When run under node, we eval the script into the current
// context so the IIFE exports `API` and `shareTarget` as globals.
if (typeof window === 'undefined' && typeof API === 'undefined') {
  const fs = require('node:fs');
  const vm = require('node:vm');
  const src = fs.readFileSync(__dirname + '/api.js', 'utf-8');
  vm.runInThisContext(src);
}

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) {
  if (a !== b) throw new Error(msg || `expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}

// --- TESTS -----------------------------------------------------------

test('API exposes the core surface', () => {
  assert(typeof API === 'object', 'API should be an object');
  assert(typeof API.get === 'function', 'API.get should be a function');
  assert(typeof API.post === 'function', 'API.post should be a function');
  assert(typeof API.refreshIfNeeded === 'function', 'API.refreshIfNeeded should be a function');
});

test('shareTarget is exposed as an async function', () => {
  assert(typeof shareTarget === 'function', 'shareTarget should be a function');
  assert(shareTarget.constructor.name === 'AsyncFunction', 'shareTarget should be async');
});

// --- RUNNER ----------------------------------------------------------

async function run() {
  let passed = 0, failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`✓ ${name}`);
      passed++;
    } catch (e) {
      console.error(`✗ ${name}: ${e.message}`);
      failed++;
    }
  }
  const summary = `${passed} passed, ${failed} failed`;
  console.log(summary);
  if (typeof document !== 'undefined') {
    const el = document.createElement('pre');
    el.textContent = summary;
    document.body.appendChild(el);
  }
  if (typeof process !== 'undefined' && failed > 0) process.exit(1);
}

// Auto-run in browser; explicit invocation in node.
if (typeof window !== 'undefined') {
  window.addEventListener('load', run);
} else {
  run();
}
