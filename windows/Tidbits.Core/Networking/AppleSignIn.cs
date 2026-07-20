using System.Security.Cryptography;
using System.Text;

namespace Tidbits.Core.Networking;

/// Sign in with Apple for the native Windows app (docs/APPLE-SIGNIN-WINDOWS.md).
///
/// Apple forbids loopback redirects ("must use the HTTPS protocool, include a domain name,
/// can't be an IP address or localhost"), and requesting scopes forces `form_post` — an
/// HTTP POST. So the redirect target is a tiny stateless Cloudflare Worker that 302s back
/// to the loopback listener this app already runs for Google.
///
/// Same split as GoogleOAuth: everything decision-shaped here is a PURE function (nonce
/// derivation, URL building, callback parsing, state validation) and unit-tests on the Mac;
/// only the socket and the browser launch are platform edges.
///
/// Deliberately NO client secret: we ask for `response_type=code id_token`, so Apple returns
/// the id_token directly in the form_post. We never exchange the code, so Apple's .p8
/// private key never has to ship inside a desktop binary.
public static class AppleSignIn
{
    public const string AuthEndpoint = "https://appleid.apple.com/auth/authorize";

    /// The Services ID (NOT the app bundle id) — the same one web sign-in uses, and the
    /// identifier the Return URL below is registered against. Not a secret.
    public const string DefaultServicesId = "com.learningischange.tidbitstrivia.web";

    /// The deployed bounce. Registered as a Return URL on the Services ID.
    public const string DefaultRedirectUri = "https://tidbits-auth.benwilkoff.workers.dev/apple/callback";

    public sealed record Config(string ServicesId, string RedirectUri)
    {
        public static readonly Config Default = new(
            Environment.GetEnvironmentVariable("TIDBITS_APPLE_SERVICES_ID") ?? DefaultServicesId,
            Environment.GetEnvironmentVariable("TIDBITS_APPLE_REDIRECT_URI") ?? DefaultRedirectUri);

        public bool IsConfigured => !string.IsNullOrWhiteSpace(ServicesId) && !string.IsNullOrWhiteSpace(RedirectUri);
    }

    // MARK: - Nonce (pure)

    /// Apple embeds SHA256(nonce) in the id_token; Firebase is handed the RAW nonce and
    /// verifies the pair. Mirrors the Apple/Swift `AppleNonce` helper.
    public static string NewRawNonce() => Base64Url(RandomNumberGenerator.GetBytes(32));

    public static string Sha256Hex(string raw)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        var sb = new StringBuilder(hash.Length * 2);
        foreach (var b in hash) sb.Append(b.ToString("x2"));
        return sb.ToString();
    }

    public static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    // MARK: - State (pure) — "<nonce>.<port>", the Worker's contract

    /// The Worker needs the ephemeral loopback port, but Apple only allows ONE
    /// pre-registered redirect URI — so the port rides in `state`. The nonce half keeps
    /// doing CSRF duty and is the only half that comes back.
    public static string BuildState(string csrfNonce, int port) => $"{csrfNonce}.{port}";

    /// Extract the loopback port from an outbound state (the app's own value).
    public static int? PortFromState(string state)
    {
        var dot = state?.LastIndexOf('.') ?? -1;
        if (dot <= 0 || dot == state!.Length - 1) return null;
        return int.TryParse(state[(dot + 1)..], out var p) && p is >= 1024 and <= 65535 ? p : null;
    }

    // MARK: - Authorize URL (pure)

    public static string BuildAuthUrl(Config config, string hashedNonce, string state)
    {
        var q = new Dictionary<string, string>
        {
            ["client_id"] = config.ServicesId,
            ["redirect_uri"] = config.RedirectUri,
            // `code id_token` is what lets us skip the code exchange (and the .p8 secret).
            ["response_type"] = "code id_token",
            ["scope"] = "name email",
            // Requesting scopes REQUIRES form_post (Apple's rule) — the Worker absorbs it.
            ["response_mode"] = "form_post",
            ["state"] = state,
            ["nonce"] = hashedNonce,
        };
        return AuthEndpoint + "?" + string.Join("&", q.Select(kv =>
            $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));
    }

    // MARK: - Callback parsing (pure)

    /// What the Worker forwards to the loopback as a GET query.
    public sealed record Callback(string? IdToken, string? Code, string? State, string? Error, string? User);

    public static Callback ParseCallback(string raw)
    {
        var query = raw ?? "";
        var q = query.IndexOf('?');
        if (q >= 0) query = query[(q + 1)..];
        var h = query.IndexOf('#');
        if (h >= 0) query = query[..h];

        string? idToken = null, code = null, state = null, error = null, user = null;
        foreach (var pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = pair.IndexOf('=');
            if (eq <= 0) continue;
            var key = Uri.UnescapeDataString(pair[..eq]);
            var val = Uri.UnescapeDataString(pair[(eq + 1)..].Replace('+', ' '));
            switch (key)
            {
                case "id_token": idToken = val; break;
                case "code": code = val; break;
                case "state": state = val; break;
                case "error": error = val; break;
                case "user": user = val; break;
            }
        }
        return new Callback(idToken, code, state, error, user);
    }

    /// The Worker returns ONLY the nonce half of state. Constant-time compare.
    public static bool StateMatches(string? expectedCsrfNonce, string? returned) =>
        !string.IsNullOrEmpty(expectedCsrfNonce) && !string.IsNullOrEmpty(returned) &&
        CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expectedCsrfNonce), Encoding.UTF8.GetBytes(returned));
}
