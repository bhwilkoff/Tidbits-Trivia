import { parseState, loopbackUrl } from './state.js';

/**
 * tidbits-auth — the HTTPS bounce that makes "Sign in with Apple" possible on Windows.
 * See docs/APPLE-SIGNIN-WINDOWS.md.
 *
 * WHY THIS EXISTS: Apple's redirect_uri "must use the HTTPS protocool, include a domain
 * name, can't be an IP address or localhost" (Apple's own docs, typo theirs), so the
 * RFC-8252 loopback pattern the Google flow uses is not available. And because we request
 * scopes (name/email), Apple uses response_mode=form_post — an HTTP POST — which a static
 * host cannot receive (GitHub Pages answers 405; Firebase Hosting needs the paid Blaze
 * plan to serve anything dynamic). So a tiny dynamic HTTPS endpoint is unavoidable; Apple
 * itself documents this bounce pattern for platforms without a native SDK.
 *
 * WHAT IT DOES: absorbs Apple's POST and 302s the browser to the desktop app's loopback
 * listener, which is a top-level NAVIGATION (allowed) and never a fetch (which browsers
 * would block as mixed content / private-network access).
 *
 * WHAT IT DELIBERATELY IS NOT: it holds NO secrets and keeps NO state. The app asks Apple
 * for `response_type=code id_token`, so the id_token arrives directly in the form_post —
 * we never exchange the code, so we never need Apple's .p8 client-secret JWT, and the
 * Apple private key never has to ship inside a desktop binary. This mirrors the Google
 * flow's no-client-secret property (PKCE is the proof there; the nonce is here).
 */

const SECURITY_HEADERS = {
  'content-type': 'text/html; charset=utf-8',
  'cache-control': 'no-store',
  'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff',
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    switch (url.pathname) {
      case '/apple/callback': return appleCallback(request);
      case '/health':         return new Response('ok', { headers: { 'cache-control': 'no-store' } });
      default:                return new Response('Not found', { status: 404 });
    }
  },
};

async function appleCallback(request) {
  // Apple form_posts here. Anything else is not Apple.
  if (request.method !== 'POST') {
    return page(405, 'Method not allowed', 'This endpoint only accepts the sign-in redirect from Apple.');
  }

  let form;
  try { form = await request.formData(); }
  catch { return page(400, "Sign-in didn't complete", 'The response from Apple could not be read. Please try again from the app.'); }

  // Fail closed on a malformed/absent state — this is the open-redirect guard.
  const parsed = parseState(form.get('state'));
  if (!parsed) {
    return page(400, "Sign-in didn't complete", 'That sign-in link was not valid. Please start again from Tidbits Trivia.');
  }

  // Hand everything useful back to the app. `user` (the display name) is Apple's
  // first-authorization-only payload; the email travels inside the id_token every time.
  const destination = loopbackUrl(parsed.port, {
    id_token: form.get('id_token'),
    code:     form.get('code'),
    error:    form.get('error'),
    user:     form.get('user'),
    state:    parsed.nonce,          // the app compares this half; the port never returns
  });

  // A 302 navigation — NOT a fetch. Browsers permit an HTTPS page to navigate to a
  // loopback URL (the Google flow already relies on exactly this hop in production).
  return new Response(null, { status: 302, headers: { location: destination, 'cache-control': 'no-store' } });
}

/** A plain, honest page for the failure paths. No tracking, no third-party anything. */
function page(status, title, body) {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  return new Response(
    `<!doctype html><meta charset=utf-8><title>${esc(title)}</title>` +
    `<body style="font-family:system-ui;background:#FBF3E4;color:#1A1714;display:flex;` +
    `align-items:center;justify-content:center;height:100vh;margin:0">` +
    `<div style="text-align:center;max-width:26rem;padding:2rem">` +
    `<h1 style="font-size:1.5rem;margin:0 0 .5rem">${esc(title)}</h1>` +
    `<p style="opacity:.7;margin:0">${esc(body)}</p></div>`,
    { status, headers: SECURITY_HEADERS },
  );
}
