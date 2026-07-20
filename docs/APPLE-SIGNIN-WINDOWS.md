# Sign in with Apple on Windows — the $0 HTTPS bounce

**Status: COMPLETE 2026-07-20 — Worker deployed + live-verified, app path built (270 tests),
Apple Return URL registered + persistence-verified.** The only thing never exercised is a
real Windows user clicking through Apple's consent screen.

Windows already has Google sign-in (RFC 8252 loopback + PKCE). Apple needs a different
shape, and this is why.

## Why the Google pattern doesn't work

Apple's `redirect_uri` doc, verbatim (the `protocool` typo is Apple's):

> The destination URI associated to your app, to which the authorization redirects. The URI
> **must use the HTTPS protocool, include a domain name, can't be an IP address or
> localhost**, and must not contain a fragment identifer (#).

So `http://127.0.0.1:<port>` — the whole basis of the Google desktop flow — is excluded by
name, twice over (not HTTPS, and an IP address).

And because we need the **email** (the identity spine is keyed on `sha256(verified email)`),
we must request scopes. Apple:

> Valid values are `query`, `fragment`, and `form_post`. **If you requested any scopes, the
> value must be `form_post`.**
>
> For the `form_post` value, **an HTTP POST request** containing the results of the
> authorization is sent to the `redirectURI`.

**Scopes ⇒ `form_post` ⇒ Apple POSTs.** That single fact eliminates static hosting.

## What we can and can't host on (measured, not assumed)

| Host | POST | Verdict |
|---|---|---|
| GitHub Pages (`tidbitstrivia.com`) | **405** | ❌ Out — measured against the live site |
| Firebase Hosting | — | ❌ Dynamic needs **Blaze (paid)**; breaks the $0 guardrail |
| Firebase `__/auth/handler` | **200** | ⚠️ Free + already Apple-registered, but it's strictly the Firebase **JS SDK** browser handshake; a native app can't harvest a token from it |
| **Cloudflare Worker** | **200** | ✅ **Chosen** |

Apple itself documents the bounce pattern for platforms with no native SDK: *"must handle
the data resulting from the authorization flow by storing it on their app server in the
logic of their `redirect_uri` endpoint. You then redirect… to give control back to the
app."* **There is no option that avoids hosting something.**

## The design

```
Windows app                Apple                   Cloudflare Worker        Windows app
-----------                -----                   -----------------        -----------
bind loopback :P
open browser ───────────▶ appleid.apple.com
                          user consents
                                 │ form_post (POST)
                                 ▼
                          https://tidbits-auth.benwilkoff.workers.dev/apple/callback
                                 │ parse state -> port, 302 (a NAVIGATION)
                                 ▼
                                              http://127.0.0.1:P/?id_token=…&state=<nonce>
                                                                          │
                          FirebaseRtdb.SignInWithApple(idToken, rawNonce) ◀┘
```

**`response_type=code id_token`** is load-bearing: Apple returns the `id_token` **directly
in the form_post**, so we never exchange the code — which means we never need Apple's `.p8`
client-secret JWT and **the Apple private key never ships inside a desktop binary**. The
Worker holds **zero secrets** and **zero state**. This mirrors the Google flow's
no-client-secret property (PKCE proves it there; the nonce proves it here).

The final hop must be a **navigation (302)**, never a `fetch()` — browsers permit an HTTPS
page to *navigate* to loopback (the Google flow relies on exactly this in production today)
but *block* an HTTPS→loopback fetch as mixed content / private-network access.

## The open-redirect guard (the security-critical part)

The Worker redirects to a destination derived from `state`, which round-trips through Apple
and is therefore attacker-influencable. Done naively that is a **phishing primitive on a
domain Apple trusts**. So:

- The scheme and host are **hard-coded constants**. Nothing from the request can change them.
- Only a **validated numeric port** (1024–65535, digits only, no leading zeros) is taken
  from `state`.
- Anything malformed **fails closed** (400).
- `state` keeps its CSRF job: it's `<nonce>.<port>`, and **only the nonce half is returned
  to the app**, which compares it. The port never comes back.

Proven by 9 unit tests (`workers/tidbits-auth/test/`) *and* against the deployed Worker:

| Attack | Live result |
|---|---|
| `state=https://evil.example.com` | 400 |
| `state=<nonce>.evil.com` | 400 |
| `state=<nonce>.53219@evil.com` | 400 |
| Ports 80 / 443 / 22 / 1023 / 65536 | 400 |
| GET instead of POST | 405 |

## Cost

**$0.** Cloudflare Workers free tier: 100k requests/**day**, no credit card. This Worker
fires **once per Apple sign-in on Windows** — a rounding error. Note the quota is per
**account**, shared with the other Workers on it.

## Deploy

```bash
cd workers/tidbits-auth && npm test && npx wrangler deploy
```

Live at **`https://tidbits-auth.benwilkoff.workers.dev`** (account `benwilkoff@gmail.com`).

> **Ownership note:** the Worker lives on a *personal* Cloudflare account while the rest of
> the Tidbits stack (Apple, Google Cloud, Firebase) is under `ben@learningischange.com`.
> Functionally irrelevant; worth consolidating if the company's asset ownership ever matters.

## Apple portal registration — DONE 2026-07-20

Registered on the Services ID `com.learningischange.tidbitstrivia.web` (Team `L2G756LY8N`,
identifier confirmed from the DOM so a silent typo couldn't slip through):

| | Value |
|---|---|
| Domain added | `tidbits-auth.benwilkoff.workers.dev` |
| Return URL added | `https://tidbits-auth.benwilkoff.workers.dev/apple/callback` |

**Web sign-in was left untouched** — `tidbitstrivia.com` and
`tidbits-trivia-f2ddb.firebaseapp.com` plus the Firebase `__/auth/handler` Return URL are
all still registered (Apple confirmed "5 Website URLs" at save). Re-opened the config after
a fresh page load to verify persistence, and read the stored Return URL back out of the DOM
to confirm it matches `AppleSignIn.DefaultRedirectUri` character-for-character.

> Apple notes settings can take **5 minutes to a few hours** to propagate, so a sign-in
> attempted immediately after registration may fail before it starts working.

## The one thing still unverified

Nobody has completed a real Apple sign-in from Windows. Every layer is proven in isolation
— the Worker against its deployed URL, the pure app logic by 270 tests, the portal config
read back from Apple — but the end-to-end handshake (real consent → real id_token → Firebase
→ email-keyed profile) needs a human on a Windows machine. Expect the first run to surface
something; the likely candidates are propagation delay and the nonce round-trip.
