// The pure, testable core of the Club entitlement webhook (docs/CLUB-MONETIZATION-BUILD.md,
// MONETIZATION §7). A Merchant-of-Record (Lemon Squeezy / Paddle) POSTs a purchase event to
// the Worker; the Worker verifies it and writes entitlements/{sha256(email)} via Firebase
// admin (the ONLY writer — clients are .write:false, R-MON-3).
//
// Everything here is a pure function so it unit-tests in Node's WebCrypto with no secrets
// and no network. The impure admin write lives in admin.js.
//
// MoR NOTE: the signature scheme + event field names below follow **Lemon Squeezy**
// (HMAC-SHA256 hex in `X-Signature`; payload `{meta:{event_name}, data:{attributes:{...}}}`).
// Paddle uses a different signature header and shape — swap `verifySignature`/`mapEvent` if
// the owner picks Paddle. The rest (emailToKey, the entitlement payload, the admin write) is
// MoR-agnostic.

/** sha256 hex of the normalized email — the same accountKey the identity spine uses. */
export async function emailToKey(email) {
  const norm = String(email || '').trim().toLowerCase();
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(norm));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Constant-time hex compare — never leak signature-match timing. */
function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Verify a Lemon-Squeezy-style HMAC-SHA256 signature over the RAW request body.
 * `rawBody` must be the exact bytes received (a re-serialized JSON will not match).
 * Fails closed on any missing input.
 */
export async function verifySignature(rawBody, signatureHeader, secret) {
  if (!rawBody || !signatureHeader || !secret) return false;
  const keyData = new TextEncoder().encode(secret);
  const key = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = typeof rawBody === 'string' ? new TextEncoder().encode(rawBody) : rawBody;
  const mac = await crypto.subtle.sign('HMAC', key, bytes);
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return timingSafeEqualHex(hex, String(signatureHeader).trim().toLowerCase());
}

/**
 * Map a MoR event to a decision: who (email), and grant-or-revoke Club with an expiry.
 * Returns null when the event isn't purchase-relevant (ignore it, ack 200).
 *
 * @returns {{email:string, grant:boolean, until:number|null, source:string} | null}
 */
export function mapEvent(event) {
  const name = event?.meta?.event_name;
  const attrs = event?.data?.attributes || {};
  const email = attrs.user_email || attrs.email || event?.meta?.custom_data?.email;
  if (!email || !name) return null;

  const ms = (iso) => (iso ? Date.parse(iso) : NaN);

  // One-time purchase (Founding Member lifetime, venue pack) → lifetime grant.
  if (name === 'order_created') {
    const paid = attrs.status === 'paid' || attrs.status === 'active';
    return paid ? { email, grant: true, until: null, source: 'web' } : null;
  }

  // A refunded one-time purchase has to REVOKE, and this was the one hole in the
  // lifecycle: a lifetime grant has `until: null`, so nothing else can ever expire
  // it. A subscription that lapses stops being renewed and times out on its own; a
  // refunded Founding Member would have kept Club forever, for free.
  if (name === 'order_refunded') {
    return { email, grant: false, until: null, source: 'web' };
  }

  // Subscription lifecycle.
  if (name.startsWith('subscription_')) {
    const status = attrs.status;                    // active | on_trial | paused | past_due | unpaid | cancelled | expired
    if (status === 'expired' || status === 'unpaid') {
      return { email, grant: false, until: null, source: 'web' };
    }
    // Active (incl. cancelled-but-not-yet-ended): valid until the period end / next renewal.
    // Prefer ends_at (set when cancelled) then renews_at; a renewal fires a fresh webhook
    // that extends it, so a lapsed sub with no further webhook naturally expires.
    const until = ms(attrs.ends_at) || ms(attrs.renews_at) || null;
    const grant = status === 'active' || status === 'on_trial' || status === 'cancelled' || status === 'past_due';
    return { email, grant, until: Number.isNaN(until) ? null : until, source: 'web' };
  }

  return null;   // disputes and everything else — ignored, ack 200
}

/**
 * Merge a decision into the existing entitlement record (additive `sources`, monotonic).
 * A revoke sets `until` into the past rather than deleting, so history is preserved.
 */
export function applyDecision(existing, decision, nowMs) {
  const sources = new Set([...(existing?.sources || []), decision.source]);
  if (decision.grant) {
    return {
      tier: 'club',
      sources: [...sources],
      since: existing?.since ?? nowMs,
      until: decision.until,          // null = lifetime
      ver: 1,
    };
  }
  // Revoke: keep the record, expire it now (so `grantsClub` returns false everywhere).
  return {
    tier: 'club',
    sources: [...sources],
    since: existing?.since ?? nowMs,
    until: nowMs - 1,
    ver: 1,
  };
}
