import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseState, loopbackUrl, MIN_PORT, MAX_PORT } from '../src/state.js';

// The Worker redirects a browser to a destination derived from `state`, which round-trips
// through Apple and is therefore attacker-influencable. These tests exist to prove the
// open-redirect guard holds — they are the security contract, not coverage padding.

test('accepts a well-formed nonce.port state', () => {
  const s = parseState('Zm9vYmFyYmF6cXV4MTIz.53219');
  assert.deepEqual(s, { nonce: 'Zm9vYmFyYmF6cXV4MTIz', port: 53219 });
});

test('the port half must be a plain in-range integer', () => {
  const nonce = 'Zm9vYmFyYmF6cXV4MTIz';
  for (const bad of ['0', '80', '443', '1023', '65536', '99999', '+53219', '0x50', '53219 ',
                     ' 53219', '53.219', '-1', '', 'abcde', '053219']) {
    assert.equal(parseState(`${nonce}.${bad}`), null, `port "${bad}" must be rejected`);
  }
  assert.equal(parseState(`${nonce}.${MIN_PORT}`)?.port, MIN_PORT);
  assert.equal(parseState(`${nonce}.${MAX_PORT}`)?.port, MAX_PORT);
});

test('the nonce half must be a long unguessable base64url token', () => {
  for (const bad of ['', 'short', 'has space here!!!!!!', 'semi;colon;injected!!', '../../etc']) {
    assert.equal(parseState(`${bad}.53219`), null, `nonce "${bad}" must be rejected`);
  }
});

test('malformed states fail closed', () => {
  for (const bad of [null, undefined, 42, {}, '', '.', '.53219', 'nonceonly',
                     'Zm9vYmFyYmF6cXV4MTIz.', 'x'.repeat(300) + '.53219']) {
    assert.equal(parseState(bad), null, `state ${JSON.stringify(bad)} must be rejected`);
  }
});

test('a state carrying a URL cannot redirect anywhere but loopback', () => {
  // The attack: smuggle a destination in. Every shape must fail to parse.
  for (const evil of ['https://evil.example.com', 'https://evil.example.com.53219',
                      '//evil.example.com.53219', 'Zm9vYmFyYmF6cXV4MTIz.evil.com',
                      'Zm9vYmFyYmF6cXV4MTIz.53219@evil.com']) {
    assert.equal(parseState(evil), null, `"${evil}" must be rejected`);
  }
});

test('loopbackUrl only ever targets 127.0.0.1 over http', () => {
  const url = new URL(loopbackUrl(53219, { id_token: 'abc', state: 'nonce' }));
  assert.equal(url.protocol, 'http:');
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.port, '53219');
  assert.equal(url.searchParams.get('id_token'), 'abc');
  assert.equal(url.searchParams.get('state'), 'nonce');
});

test('loopbackUrl refuses an out-of-range port rather than building a bad redirect', () => {
  for (const bad of [0, 80, 1023, 65536, -1, 1.5, NaN, '53219']) {
    assert.throws(() => loopbackUrl(bad), /invalid port/);
  }
});

test('loopbackUrl percent-encodes values instead of letting them inject params', () => {
  const url = new URL(loopbackUrl(53219, { user: '{"name":"A B"}&injected=1' }));
  assert.equal(url.searchParams.get('injected'), null);        // not smuggled in as its own param
  assert.equal(url.searchParams.get('user'), '{"name":"A B"}&injected=1');
});

test('empty and absent values are omitted, not sent as blanks', () => {
  const url = new URL(loopbackUrl(53219, { id_token: 'abc', code: '', error: null, user: undefined }));
  assert.equal(url.searchParams.has('code'), false);
  assert.equal(url.searchParams.has('error'), false);
  assert.equal(url.searchParams.has('user'), false);
  assert.equal(url.searchParams.get('id_token'), 'abc');
});
