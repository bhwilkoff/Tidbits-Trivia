namespace Tidbits.Core.Networking;

/// Composes the desktop OAuth flow into a single "sign in with Google" verb for the UI.
///
/// The whole point of the split is that everything decision-shaped
/// (`GoogleOAuth.BuildAuthUrl` / `ParseCallback` / `StateMatches` / PKCE) is pure and
/// tested on the Mac, and this class only sequences them. The two edges — a real
/// loopback socket and a real browser — are injectable.
public sealed class WindowsSignIn
{
    private readonly FirebaseRtdb _db;
    private readonly GoogleOAuth.Config _config;
    private readonly IBrowserLauncher _browser;
    private readonly HttpClient _http;

    public WindowsSignIn(
        FirebaseRtdb db,
        GoogleOAuth.Config? config = null,
        IBrowserLauncher? browser = null,
        HttpClient? http = null)
    {
        _db = db;
        _config = config ?? GoogleOAuth.Config.Default;
        _browser = browser ?? new SystemBrowserLauncher();
        _http = http ?? new HttpClient();
    }

    public bool IsConfigured => _config.IsConfigured;

    /// How long to wait for the browser redirect before giving up. Long enough to create
    /// a Google account mid-flow; short enough that an abandoned attempt frees the socket.
    public TimeSpan Timeout { get; init; } = TimeSpan.FromMinutes(5);

    /// Full round trip: open the browser, wait for the loopback redirect, exchange the
    /// code, hand the id_token to Firebase. Returns the federated result so the caller
    /// can re-key the profile by verified email.
    ///
    /// Cancellation is honored so a user who closes the sign-in sheet doesn't leave a
    /// socket bound forever.
    public async Task<FirebaseRtdb.FederatedResult> SignInWithGoogle(CancellationToken ct = default)
    {
        if (!_config.IsConfigured) throw new OAuthNotConfiguredException();

        var pkce = GoogleOAuth.CreatePkce();
        var state = GoogleOAuth.Base64Url(Guid.NewGuid().ToByteArray());

        using var listener = new LoopbackAuthListener();
        var url = GoogleOAuth.BuildAuthUrl(_config, listener.RedirectUri, pkce.Challenge, state);
        _browser.Open(url);

        // Bound the wait. A user who closes the consent tab never produces a callback, and
        // an unbounded wait leaves the socket bound and the sign-in button dead forever.
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(Timeout);

        GoogleOAuth.Callback cb;
        try { cb = await listener.WaitForCallback(timeout.Token); }
        catch (Exception) when (timeout.IsCancellationRequested && !ct.IsCancellationRequested)
        {
            throw new OAuthDeniedException("timeout");
        }
        if (cb.Error is { } err) throw new OAuthDeniedException(err);
        if (!GoogleOAuth.StateMatches(state, cb.State)) throw new OAuthDeniedException("state_mismatch");
        if (cb.Code is not { } code) throw new OAuthDeniedException("no_code");

        var idToken = await GoogleOAuth.ExchangeCodeForIdToken(
            _config, code, pkce.Verifier, listener.RedirectUri, _http);
        return await _db.SignInWithGoogle(idToken);
    }

    /// Sign in with Apple (docs/APPLE-SIGNIN-WINDOWS.md). Apple can't redirect to loopback,
    /// so the browser lands on the HTTPS bounce Worker, which 302s back here with the
    /// id_token. We never exchange the code — so no Apple .p8 secret ever ships in the app.
    public async Task<FirebaseRtdb.FederatedResult> SignInWithApple(CancellationToken ct = default)
    {
        var cfg = AppleSignIn.Config.Default;
        if (!cfg.IsConfigured) throw new OAuthNotConfiguredException();

        // Apple embeds SHA256(nonce) in the id_token; Firebase verifies against the RAW one.
        var rawNonce = AppleSignIn.NewRawNonce();
        var csrf = AppleSignIn.Base64Url(Guid.NewGuid().ToByteArray());

        using var listener = new LoopbackAuthListener();
        var state = AppleSignIn.BuildState(csrf, listener.Port);   // the Worker reads the port back out
        _browser.Open(AppleSignIn.BuildAuthUrl(cfg, AppleSignIn.Sha256Hex(rawNonce), state));

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(Timeout);

        string rawQuery;
        try { rawQuery = await listener.WaitForRawQuery(timeout.Token); }
        catch (Exception) when (timeout.IsCancellationRequested && !ct.IsCancellationRequested)
        {
            throw new OAuthDeniedException("timeout");
        }

        var cb = AppleSignIn.ParseCallback(rawQuery);
        if (cb.Error is { } err) throw new OAuthDeniedException(err);
        // The Worker returns ONLY the nonce half of state — compare against that.
        if (!AppleSignIn.StateMatches(csrf, cb.State)) throw new OAuthDeniedException("state_mismatch");
        if (cb.IdToken is not { } idToken) throw new OAuthDeniedException("no_id_token");

        return await _db.SignInWithApple(idToken, rawNonce);
    }
}

/// The user declined, the callback was forged, or Google returned an error. Separate
/// from a transport failure so the UI can stay quiet on a plain cancel.
public sealed class OAuthDeniedException(string reason)
    : Exception($"Google sign-in did not complete ({reason}).")
{
    public string Reason { get; } = reason;

    /// A user closing the consent tab is not an error worth surfacing loudly.
    public bool IsUserCancellation => Reason is "access_denied" or "no_code";
}
