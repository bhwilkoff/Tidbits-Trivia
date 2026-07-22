import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emailToKey, verifySignature, mapEvent, applyDecision } from '../src/entitlements.js';

// The webhook writes a Club entitlement keyed by sha256(email). These pin the
// security-critical + MoR-mapping logic; the admin write (network) is out of scope here.

test('emailToKey is sha256 of the normalized email — matches the identity spine', async () => {
  // shasum -a 256 of "test@example.com"
  assert.equal(await emailToKey('test@example.com'),
    '973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b');
  assert.equal(await emailToKey('  Test@Example.COM  '),
    '973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b');
});

test('verifySignature accepts a correct HMAC and rejects a tampered one', async () => {
  const secret = 'whsec_test';
  const body = JSON.stringify({ meta: { event_name: 'order_created' } });
  // compute the expected signature the same way the MoR would
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  const sig = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');

  assert.equal(await verifySignature(body, sig, secret), true);
  assert.equal(await verifySignature(body, sig.toUpperCase(), secret), true);   // case-insensitive
  assert.equal(await verifySignature(body + 'x', sig, secret), false);          // body tampered
  assert.equal(await verifySignature(body, sig, 'wrong_secret'), false);        // wrong secret
});

test('verifySignature fails closed on missing inputs', async () => {
  assert.equal(await verifySignature('', 'sig', 'secret'), false);
  assert.equal(await verifySignature('body', '', 'secret'), false);
  assert.equal(await verifySignature('body', 'sig', ''), false);
});

test('mapEvent grants lifetime on a paid one-time order', () => {
  const d = mapEvent({ meta: { event_name: 'order_created' },
    data: { attributes: { user_email: 'a@b.com', status: 'paid' } } });
  assert.deepEqual(d, { email: 'a@b.com', grant: true, until: null, source: 'web' });
});

test('mapEvent grants a subscription until its renewal', () => {
  const renews = '2027-07-21T00:00:00.000Z';
  const d = mapEvent({ meta: { event_name: 'subscription_created' },
    data: { attributes: { user_email: 'a@b.com', status: 'active', renews_at: renews } } });
  assert.equal(d.grant, true);
  assert.equal(d.until, Date.parse(renews));
});

test('mapEvent keeps a cancelled sub until its end date, then revokes on expiry', () => {
  const ends = '2027-01-01T00:00:00.000Z';
  const cancelled = mapEvent({ meta: { event_name: 'subscription_updated' },
    data: { attributes: { user_email: 'a@b.com', status: 'cancelled', ends_at: ends } } });
  assert.equal(cancelled.grant, true);            // still valid until period end
  assert.equal(cancelled.until, Date.parse(ends));

  const expired = mapEvent({ meta: { event_name: 'subscription_expired' },
    data: { attributes: { user_email: 'a@b.com', status: 'expired' } } });
  assert.equal(expired.grant, false);
});

test('mapEvent ignores irrelevant or malformed events', () => {
  assert.equal(mapEvent({ meta: { event_name: 'order_refunded' }, data: { attributes: { user_email: 'a@b.com' } } }), null);
  assert.equal(mapEvent({ meta: { event_name: 'order_created' }, data: { attributes: {} } }), null);   // no email
  assert.equal(mapEvent({}), null);
  assert.equal(mapEvent(null), null);
});

test('applyDecision grants club, is additive on sources, and preserves since', () => {
  const now = 1_800_000_000_000;
  const granted = applyDecision(null, { grant: true, until: null, source: 'web' }, now);
  assert.equal(granted.tier, 'club');
  assert.deepEqual(granted.sources, ['web']);
  assert.equal(granted.since, now);
  assert.equal(granted.until, null);

  // a later apple mirror keeps the original since and adds the source
  const both = applyDecision(granted, { grant: true, until: null, source: 'apple' }, now + 1000);
  assert.deepEqual(both.sources.sort(), ['apple', 'web']);
  assert.equal(both.since, now);
});

test('applyDecision revokes by expiring in the past, never by deleting', () => {
  const now = 1_800_000_000_000;
  const revoked = applyDecision({ tier: 'club', sources: ['web'], since: 1 }, { grant: false, source: 'web' }, now);
  assert.equal(revoked.tier, 'club');           // record preserved
  assert.ok(revoked.until < now);               // but expired
});
