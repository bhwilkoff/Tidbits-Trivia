// The security-critical pure logic of the auth bounce, split out so it is unit-testable
// without a Worker runtime (docs/APPLE-SIGNIN-WINDOWS.md).
//
// THE THREAT: this Worker takes a destination derived from an attacker-influencable
// parameter (`state`, which round-trips through Apple) and redirects a browser to it. Done
// naively that is a textbook OPEN REDIRECT — a phishing primitive on a domain that Apple
// trusts. So the destination is NEVER taken from input: the host is hard-coded to the
// loopback and only a validated numeric PORT is accepted from `state`.

export const LOOPBACK_HOST = '127.0.0.1';
export const MIN_PORT = 1024;    // below this is privileged; the app binds an ephemeral port
export const MAX_PORT = 65535;

/**
 * Parse the `state` the app sent, shaped "<nonce>.<port>".
 *
 * The port rides in `state` because Apple requires a single PRE-REGISTERED redirect URI,
 * but the app's loopback port is ephemeral per attempt — so the Worker has to learn it at
 * runtime. `state` keeps its CSRF job: the nonce half is returned to the app, which
 * compares it. The port half is never trusted as anything but a number.
 *
 * @returns {{nonce: string, port: number} | null} null on ANY malformed input (fail closed).
 */
export function parseState(state) {
  if (typeof state !== 'string' || state.length > 256) return null;
  const dot = state.lastIndexOf('.');
  if (dot <= 0 || dot === state.length - 1) return null;

  const nonce = state.slice(0, dot);
  const portRaw = state.slice(dot + 1);

  // base64url nonce, long enough to be an unguessable CSRF token.
  if (!/^[A-Za-z0-9_-]{16,200}$/.test(nonce)) return null;
  // Digits only — no "+1", no "0x50", no whitespace, no leading zeros games.
  if (!/^[1-9][0-9]{3,4}$/.test(portRaw)) return null;

  const port = Number(portRaw);
  if (!Number.isInteger(port) || port < MIN_PORT || port > MAX_PORT) return null;
  return { nonce, port };
}

/**
 * Build the ONLY destination this Worker will ever redirect to. The host and scheme are
 * hard-coded constants — nothing from the request can change them, which is what makes an
 * open redirect structurally impossible rather than merely unlikely.
 */
export function loopbackUrl(port, params = {}) {
  if (!Number.isInteger(port) || port < MIN_PORT || port > MAX_PORT) {
    throw new Error('refusing to build a redirect for an invalid port');
  }
  const url = new URL(`http://${LOOPBACK_HOST}:${port}/`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== null && value !== undefined && value !== '') url.searchParams.set(key, String(value));
  }
  return url.toString();
}
