using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Tidbits.Core.Networking;

/// Desktop OAuth (RFC 8252) for Google sign-in on Windows — the loopback-redirect +
/// PKCE flow, because a desktop app cannot hold a client secret and Firebase's
/// `signInWithIdp` needs a Google `id_token`.
///
/// Split deliberately: every decision here is a PURE function (URL building, callback
/// parsing, PKCE derivation) so it unit-tests on the Mac head; only the loopback
/// listener and the "open a browser" call are platform edges, and they live in
/// `LoopbackAuthListener` / `IBrowserLauncher`.
///
/// Apple sign-in is NOT here: Apple's web flow rejects `localhost` redirects (HTTPS
/// only), so Sign in with Apple on Windows needs a hosted redirect page plus the
/// `windows.protocol` URI scheme. Tracked separately; Google unblocks email-keyed
/// identity on its own.
public static class GoogleOAuth
{
    public const string AuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth";
    public const string TokenEndpoint = "https://oauth2.googleapis.com/token";

    /// The OAuth client. MUST be a **Desktop app** client in the same Google Cloud
    /// project as the Firebase app (842242746909) — a Web client cannot use a loopback
    /// redirect without a secret, and Firebase only accepts an `id_token` whose `aud`
    /// belongs to a client in the project it trusts.
    public sealed record Config(string ClientId)
    {
        /// A desktop OAuth client id is NOT a secret (PKCE is the proof, and it ships inside
        /// every installed copy anyway) — but it is deployment config, so it reads from the
        /// environment first. That keeps it out of the repo, lets CI render the signed-in UI,
        /// and lets the owner drop it in without a code change.
        public const string EnvVar = "TIDBITS_GOOGLE_CLIENT_ID";

        public static readonly Config Default = new(
            Environment.GetEnvironmentVariable(EnvVar)
            // The "Tidbits Windows (desktop)" OAuth client in Google Cloud project
            // 842242746909 (created 2026-07-20). NOT a secret: a desktop client id ships
            // inside every installed copy, and PKCE — not a client secret — is the proof
            // (the desktop client's secret is deliberately unused by this loopback flow).
            ?? "842242746909-9r4fl13sbn0v4io2614ekfgehd4c03l5.apps.googleusercontent.com");

        public bool IsConfigured => !string.IsNullOrWhiteSpace(ClientId);
    }

    // MARK: - PKCE (pure)

    public sealed record Pkce(string Verifier, string Challenge);

    /// RFC 7636 S256. The verifier is 43-128 chars of unreserved base64url.
    public static Pkce CreatePkce(byte[]? entropy = null)
    {
        var bytes = entropy ?? RandomNumberGenerator.GetBytes(32);
        var verifier = Base64Url(bytes);
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        return new Pkce(verifier, challenge);
    }

    public static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    // MARK: - URL building (pure)

    /// `redirectUri` is the loopback the listener actually bound, e.g.
    /// `http://127.0.0.1:53219/`. Google requires the port be echoed exactly.
    public static string BuildAuthUrl(Config config, string redirectUri, string challenge, string state)
    {
        var q = new Dictionary<string, string>
        {
            ["client_id"] = config.ClientId,
            ["redirect_uri"] = redirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid email profile",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = state,
            // Force the chooser so a shared Windows box doesn't silently reuse an account.
            ["prompt"] = "select_account",
        };
        return AuthEndpoint + "?" + string.Join("&", q.Select(kv =>
            $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));
    }

    // MARK: - Callback parsing (pure)

    public sealed record Callback(string? Code, string? State, string? Error);

    /// Parse the query string the browser hands back ("?code=…&state=…" or "?error=…").
    /// Accepts a bare query, a leading '?', or a full URL.
    public static Callback ParseCallback(string raw)
    {
        var query = raw;
        var qIdx = query.IndexOf('?');
        if (qIdx >= 0) query = query[(qIdx + 1)..];
        var hIdx = query.IndexOf('#');
        if (hIdx >= 0) query = query[..hIdx];

        string? code = null, state = null, error = null;
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = pair.IndexOf('=');
            if (eq <= 0) continue;
            var key = Uri.UnescapeDataString(pair[..eq]);
            var val = Uri.UnescapeDataString(pair[(eq + 1)..].Replace('+', ' '));
            switch (key)
            {
                case "code": code = val; break;
                case "state": state = val; break;
                case "error": error = val; break;
            }
        }
        return new Callback(code, state, error);
    }

    /// Constant-time-ish state comparison — a mismatched state means a forged callback.
    public static bool StateMatches(string? expected, string? actual) =>
        !string.IsNullOrEmpty(expected) && !string.IsNullOrEmpty(actual) &&
        CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(actual));

    // MARK: - Code exchange (network, but no UI)

    /// Exchange the authorization code for Google's `id_token`. No client secret —
    /// PKCE is the proof, which is exactly why the client must be a Desktop app type.
    public static async Task<string> ExchangeCodeForIdToken(
        Config config, string code, string verifier, string redirectUri, HttpClient http)
    {
        var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = config.ClientId,
            ["code"] = code,
            ["code_verifier"] = verifier,
            ["grant_type"] = "authorization_code",
            ["redirect_uri"] = redirectUri,
        });
        using var resp = await http.PostAsync(TokenEndpoint, form);
        var text = await resp.Content.ReadAsStringAsync();
        if ((int)resp.StatusCode >= 400) throw new FirebaseRtdb.RtdbException((int)resp.StatusCode);
        using var doc = JsonDocument.Parse(text);
        if (!doc.RootElement.TryGetProperty("id_token", out var t) || t.GetString() is not { } idToken)
            throw new FirebaseRtdb.RtdbException(502);
        return idToken;
    }

    /// The page the browser lands on after consent. Deliberately self-contained (the
    /// CSP-free local listener serves it) and it tells the user to go back to the app.
    public static string SuccessPageHtml(bool ok) =>
        "<!doctype html><meta charset=utf-8><title>Tidbits Trivia</title>" +
        "<body style=\"font-family:system-ui;background:#FFFDF7;color:#0A0A0A;" +
        "display:flex;align-items:center;justify-content:center;height:100vh;margin:0\">" +
        "<div style=\"text-align:center;max-width:26rem;padding:2rem\">" +
        (ok
            ? "<h1 style=\"font-size:1.5rem;margin:0 0 .5rem\">You're signed in</h1>" +
              "<p style=\"opacity:.7;margin:0\">You can close this tab and go back to Tidbits Trivia.</p>"
            : "<h1 style=\"font-size:1.5rem;margin:0 0 .5rem\">Sign-in didn't finish</h1>" +
              "<p style=\"opacity:.7;margin:0\">Close this tab and try again from Tidbits Trivia.</p>") +
        "</div>";
}

/// Thrown when Windows Google sign-in is invoked before the Desktop OAuth client id
/// is configured. Distinct from a network failure so the UI can say something useful.
public sealed class OAuthNotConfiguredException : Exception
{
    public OAuthNotConfiguredException()
        : base("Google sign-in is not configured on Windows (no Desktop OAuth client id).") { }
}
