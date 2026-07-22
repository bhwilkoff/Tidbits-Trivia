// Firebase admin write from the Worker (docs/CLUB-MONETIZATION-BUILD.md). The entitlements/
// tree is .write:false for every client (R-MON-3); only an ADMIN credential may write it.
// The Worker mints a Google OAuth access token from a service account (RS256 JWT signed
// with WebCrypto) and uses the RTDB REST API with that token — the same $0 pattern the
// reminders cron uses, done in-Worker.
//
// All secrets are Worker secrets the OWNER sets (inert until then):
//   FIREBASE_SA_EMAIL         the service-account email
//   FIREBASE_SA_PRIVATE_KEY   its PKCS#8 PEM private key
//   FIREBASE_DB_URL           https://<project>-default-rtdb.firebaseio.com

import { applyDecision } from './entitlements.js';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email';

function b64url(bytes) {
  const bin = String.fromCharCode(...new Uint8Array(bytes));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem) {
  const body = pem.replace(/-----BEGIN [^-]+-----/, '').replace(/-----END [^-]+-----/, '').replace(/\s+/g, '');
  const bin = atob(body);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der.buffer;
}

/** Mint a short-lived Google OAuth access token for the RTDB admin scope. */
async function accessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: env.FIREBASE_SA_EMAIL, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  })));
  const signingInput = `${header}.${claims}`;

  const key = await crypto.subtle.importKey('pkcs8', pemToDer(env.FIREBASE_SA_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${b64url(sig)}`;

  const resp = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${jwt}`,
  });
  if (!resp.ok) throw new Error(`token exchange ${resp.status}`);
  return (await resp.json()).access_token;
}

/** True when the admin credentials are present (else the webhook 503s so the MoR retries). */
export function adminConfigured(env) {
  return !!(env && env.FIREBASE_SA_EMAIL && env.FIREBASE_SA_PRIVATE_KEY && env.FIREBASE_DB_URL);
}

/** Read the existing entitlement, merge the decision, write it back — as admin. */
export async function writeEntitlement(env, key, decision) {
  const token = await accessToken(env);
  const base = `${env.FIREBASE_DB_URL.replace(/\/$/, '')}/entitlements/${key}.json?access_token=${token}`;

  const getResp = await fetch(base);
  const existing = getResp.ok ? await getResp.json() : null;

  const merged = applyDecision(existing, decision, Date.now());
  const putResp = await fetch(base, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(merged),
  });
  if (!putResp.ok) throw new Error(`rtdb write ${putResp.status}`);
  return merged;
}
