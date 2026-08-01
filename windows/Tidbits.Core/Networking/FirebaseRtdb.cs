using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// Firebase Realtime Database over its REST + SSE API — the C# twin of js/firebase.js
/// and the Swift FirebaseRTDB, no SDK (HttpClient only). Anonymous auth via Identity
/// Toolkit; reads/writes via the RTDB `.json` REST API; live updates via Server-Sent
/// Events. Same project + non-secret config as web/Android, so all clients meet in ONE
/// room; access is gated by Security Rules + anon-auth, not by hiding the config.
public sealed class FirebaseRtdb
{
    public sealed record Config(string ApiKey, string DatabaseUrl);

    /// The committed non-secret web config (same project as js/firebase-config.js).
    public static readonly Config DefaultConfig = new(
        "AIzaSyCns8iba6zVqkddEUY_gqoc4eVxz-3BGaA",
        "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com");

    public const string RefreshKey = "tidbits.fb.anonRefresh";

    private readonly Config _config;
    private readonly HttpClient _http;
    private readonly ITokenStore _tokens;
    private readonly SemaphoreSlim _authLock = new(1, 1);

    private string? _idToken;
    private string? _refreshToken;
    private DateTime _expiry = DateTime.MinValue;
    public string? Uid { get; private set; }

    public FirebaseRtdb(Config? config = null, HttpClient? http = null, ITokenStore? tokens = null)
    {
        _config = config ?? DefaultConfig;
        _http = http ?? new HttpClient();
        _tokens = tokens ?? new FileTokenStore();
    }

    public sealed record FederatedResult(string Uid, string? Email, string? DisplayName);

    public class RtdbException(int status) : Exception($"RTDB HTTP {status}") { public int Status { get; } = status; }
    public sealed class AlreadyLinkedException() : Exception("federated user already linked");

    // MARK: Auth (anonymous)

    public async Task<string> EnsureAuth()
    {
        await _authLock.WaitAsync();
        try
        {
            if (Uid is not null && DateTime.UtcNow < _expiry.AddSeconds(-300)) return Uid;
            _refreshToken ??= _tokens.Get(RefreshKey);
            if (_refreshToken is not null)
            {
                try { await RefreshSession(); }
                catch { _refreshToken = null; _tokens.Delete(RefreshKey); await SignUpAnonymous(); }
            }
            else await SignUpAnonymous();
            return Uid ?? throw new RtdbException(401);
        }
        finally { _authLock.Release(); }
    }

    private async Task SignUpAnonymous()
    {
        using var resp = await _http.PostAsync(
            $"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={_config.ApiKey}",
            new StringContent("{\"returnSecureToken\":true}", Encoding.UTF8, "application/json"));
        Check(resp);
        var r = JsonSerializer.Deserialize<SignUpResponse>(await resp.Content.ReadAsStringAsync())!;
        Apply(r.IdToken, r.RefreshToken, r.ExpiresIn, r.LocalId);
    }

    private async Task RefreshSession()
    {
        if (_refreshToken is null) { await SignUpAnonymous(); return; }
        using var resp = await _http.PostAsync(
            $"https://securetoken.googleapis.com/v1/token?key={_config.ApiKey}",
            new StringContent($"grant_type=refresh_token&refresh_token={_refreshToken}",
                Encoding.UTF8, "application/x-www-form-urlencoded"));
        Check(resp);
        var r = JsonSerializer.Deserialize<RefreshResponse>(await resp.Content.ReadAsStringAsync())!;
        Apply(r.IdToken, r.RefreshToken, r.ExpiresIn, r.UserId);
    }

    public async Task<FederatedResult> SignInWithApple(string identityToken, string rawNonce)
    {
        var post = $"id_token={identityToken}&providerId=apple.com&nonce={rawNonce}";
        var r = await SignInWithIdp(post, null);
        Apply(r.IdToken, r.RefreshToken, r.ExpiresIn, r.LocalId);
        return new FederatedResult(r.LocalId, r.Email, r.DisplayName);
    }

    /// Google sign-in. `idToken` comes from the desktop OAuth loopback flow
    /// (`GoogleOAuth`); Firebase accepts it because the OAuth client lives in the same
    /// Google Cloud project. Same shape as SignInWithApple so both converge on the
    /// email-keyed profile.
    public async Task<FederatedResult> SignInWithGoogle(string idToken)
    {
        var post = $"id_token={Uri.EscapeDataString(idToken)}&providerId=google.com";
        var r = await SignInWithIdp(post, null);
        Apply(r.IdToken, r.RefreshToken, r.ExpiresIn, r.LocalId);
        return new FederatedResult(r.LocalId, r.Email, r.DisplayName);
    }

    public string? CurrentEmail() => _idToken is null ? null : EmailFromJwt(_idToken);

    /// True when the signed-in token carries a VERIFIED email. The RTDB rules require
    /// `auth.token.email_verified === true` to write the email-keyed profile, so the UI
    /// must not promise a synced identity when this is false.
    public bool CurrentEmailVerified() => _idToken is not null && EmailVerifiedFromJwt(_idToken);

    /// Decode the `email_verified` claim. Mirrors the rule the RTDB enforces.
    public static bool EmailVerifiedFromJwt(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3) return false;
        var b64 = parts[1].Replace('-', '+').Replace('_', '/');
        while (b64.Length % 4 != 0) b64 += "=";
        try
        {
            using var doc = JsonDocument.Parse(Convert.FromBase64String(b64));
            if (!doc.RootElement.TryGetProperty("email_verified", out var v)) return false;
            return v.ValueKind == JsonValueKind.True ||
                   (v.ValueKind == JsonValueKind.String && v.GetString() == "true");
        }
        catch { return false; }
    }

    /// Decode the `email` claim from a JWT payload (Firebase ID token or Apple identity token).
    public static string? EmailFromJwt(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3) return null;
        var b64 = parts[1].Replace('-', '+').Replace('_', '/');
        while (b64.Length % 4 != 0) b64 += "=";
        try
        {
            using var doc = JsonDocument.Parse(Convert.FromBase64String(b64));
            if (doc.RootElement.TryGetProperty("email", out var e) && e.ValueKind == JsonValueKind.String)
            {
                var email = e.GetString();
                return string.IsNullOrEmpty(email) ? null : email;
            }
        }
        catch { }
        return null;
    }

    public async Task<string> SignOut()
    {
        _tokens.Delete(RefreshKey);
        _idToken = null; _refreshToken = null; Uid = null; _expiry = DateTime.MinValue;
        await SignUpAnonymous();
        return Uid ?? "";
    }

    /// Delete the CREDENTIAL itself (Identity Toolkit `accounts:delete`), then start a fresh
    /// anonymous session so the app still works afterwards. Returns the new uid.
    ///
    /// Twin of Swift `FirebaseRTDB.deleteAccount()`. This is the authoritative step of account
    /// deletion — the RTDB node deletes around it are best-effort, but if this throws the
    /// account still exists and the caller MUST report failure rather than claim success.
    public async Task<string> DeleteAccount()
    {
        await EnsureAuth();
        var body = JsonSerializer.Serialize(new Dictionary<string, string> { ["idToken"] = _idToken ?? "" });
        using var resp = await _http.PostAsync(
            $"https://identitytoolkit.googleapis.com/v1/accounts:delete?key={_config.ApiKey}",
            new StringContent(body, Encoding.UTF8, "application/json"));
        Check(resp);
        _tokens.Delete(RefreshKey);
        _idToken = null; _refreshToken = null; Uid = null; _expiry = DateTime.MinValue;
        await SignUpAnonymous();
        return Uid ?? "";
    }

    private async Task<IdpResponse> SignInWithIdp(string postBody, string? linkTo)
    {
        var body = new Dictionary<string, object>
        {
            ["postBody"] = postBody, ["requestUri"] = "http://localhost",
            ["returnSecureToken"] = true, ["returnIdpCredential"] = true,
        };
        if (linkTo is not null) body["idToken"] = linkTo;
        using var resp = await _http.PostAsync(
            $"https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key={_config.ApiKey}",
            new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"));
        var text = await resp.Content.ReadAsStringAsync();
        if ((int)resp.StatusCode >= 400)
        {
            if (text.Contains("FEDERATED_USER_ID_ALREADY_LINKED") || text.Contains("EMAIL_EXISTS"))
                throw new AlreadyLinkedException();
            throw new RtdbException((int)resp.StatusCode);
        }
        return JsonSerializer.Deserialize<IdpResponse>(text)!;
    }

    private void Apply(string idToken, string refreshToken, string expiresIn, string uid)
    {
        _idToken = idToken; _refreshToken = refreshToken; Uid = uid;
        _expiry = DateTime.UtcNow.AddSeconds(double.TryParse(expiresIn, out var s) ? s : 3600);
        _tokens.Set(RefreshKey, refreshToken);
    }

    private async Task<string> ValidToken()
    {
        await EnsureAuth();
        return _idToken ?? throw new RtdbException(401);
    }

    // MARK: REST read/write

    public Task Put<T>(string path, T value) => WriteJson(path, JsonSerializer.SerializeToUtf8Bytes(value, Wire.Json), HttpMethod.Put);
    public Task Patch<T>(string path, T value) => WriteJson(path, JsonSerializer.SerializeToUtf8Bytes(value, Wire.Json), HttpMethod.Patch);
    public Task PutJson(string path, byte[] json) => WriteJson(path, json, HttpMethod.Put);
    public Task PatchJson(string path, byte[] json) => WriteJson(path, json, HttpMethod.Patch);

    public async Task Delete(string path)
    {
        var token = await ValidToken();
        using var resp = await _http.DeleteAsync(RestUrl(path, token));
        Check(resp);
    }

    /// True if a value exists (non-null) at `path`.
    public async Task<bool> Exists(string path)
    {
        var token = await ValidToken();
        using var resp = await _http.GetAsync(RestUrl(path, token));
        Check(resp);
        var s = await resp.Content.ReadAsStringAsync();
        return s.Length > 0 && s != "null";
    }

    /// Read + deserialize the value at `path` (default(T) if absent → JSON null).
    public async Task<T?> Get<T>(string path)
    {
        var token = await ValidToken();
        using var resp = await _http.GetAsync(RestUrl(path, token));
        Check(resp);
        var s = await resp.Content.ReadAsStringAsync();
        if (s.Length == 0 || s == "null") return default;
        return JsonSerializer.Deserialize<T>(s, Wire.Json);
    }

    /// Read the RAW JSON at `path` (null if absent). A saved quiz decodes itself from
    /// the frozen contract bytes (docs/QUIZ-CONTRACT.md), so routing it through a
    /// typed Deserialize would create a SECOND representation of a format that
    /// already has four implementations.
    public async Task<string?> GetJson(string path)
    {
        var token = await ValidToken();
        using var resp = await _http.GetAsync(RestUrl(path, token));
        Check(resp);
        var s = await resp.Content.ReadAsStringAsync();
        return (s.Length == 0 || s == "null") ? null : s;
    }

    /// Write RAW JSON to `path` — the mirror of GetJson, same reasoning.
    public async Task PutJson(string path, string json)
    {
        var token = await ValidToken();
        using var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");
        using var resp = await _http.PutAsync(RestUrl(path, token), content);
        Check(resp);
    }

    /// Read a value together with its RTDB ETag, for a compare-and-set transaction
    /// (optimistic concurrency — the matchmaking queue claim, 2.21).
    public async Task<(T? Value, string ETag)> GetWithEtag<T>(string path)
    {
        var token = await ValidToken();
        using var req = new HttpRequestMessage(HttpMethod.Get, RestUrl(path, token));
        req.Headers.TryAddWithoutValidation("X-Firebase-ETag", "true");
        using var resp = await _http.SendAsync(req);
        Check(resp);
        var etag = resp.Headers.ETag?.Tag ?? "";
        var s = await resp.Content.ReadAsStringAsync();
        var value = (s.Length == 0 || s == "null") ? default : JsonSerializer.Deserialize<T>(s, Wire.Json);
        return (value, etag);
    }

    /// Conditional PUT — writes only if the value at `path` still matches `etag`.
    /// Returns false on 412 Precondition Failed (someone else won the race). Pass a
    /// null value to conditionally CLEAR the node (RTDB deletes on PUT null).
    public async Task<bool> CasPut<T>(string path, T? value, string etag)
    {
        var token = await ValidToken();
        var json = JsonSerializer.SerializeToUtf8Bytes(value, Wire.Json);
        using var req = new HttpRequestMessage(HttpMethod.Put, RestUrl(path, token))
        {
            Content = new ByteArrayContent(json),
        };
        req.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        req.Headers.TryAddWithoutValidation("if-match", etag);
        using var resp = await _http.SendAsync(req);
        if (resp.StatusCode == System.Net.HttpStatusCode.PreconditionFailed) return false;
        Check(resp);
        return true;
    }

    private async Task WriteJson(string path, byte[] json, HttpMethod method)
    {
        var token = await ValidToken();
        using var req = new HttpRequestMessage(method, RestUrl(path, token))
        {
            Content = new ByteArrayContent(json),
        };
        req.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        using var resp = await _http.SendAsync(req);
        Check(resp);
    }

    // MARK: Live streaming (SSE)

    public sealed record StreamEvent(string Event, string Path, string? DataJson);

    /// Stream live updates at `path` as SSE. Enumeration ends when the token is cancelled.
    public async IAsyncEnumerable<StreamEvent> Stream(string path, [EnumeratorCancellation] CancellationToken ct = default)
    {
        var token = await ValidToken();
        using var req = new HttpRequestMessage(HttpMethod.Get, RestUrl(path, token));
        req.Headers.Accept.ParseAdd("text/event-stream");
        using var resp = await _http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        string currentEvent = "";
        while (!ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct);
            if (line is null) break;
            if (line.StartsWith("event: ")) currentEvent = line[7..];
            else if (line.StartsWith("data: "))
            {
                var ev = ParseEvent(currentEvent, line[6..]);
                if (ev is not null) yield return ev;
            }
        }
    }

    /// Parse an RTDB SSE frame: `data: {"path":"/x","data":<value>}`.
    public static StreamEvent? ParseEvent(string @event, string payload)
    {
        if (@event == "keep-alive") return null;
        try
        {
            using var doc = JsonDocument.Parse(payload);
            var root = doc.RootElement;
            var path = root.TryGetProperty("path", out var p) && p.ValueKind == JsonValueKind.String ? p.GetString()! : "/";
            string? dataJson = null;
            if (root.TryGetProperty("data", out var d) && d.ValueKind != JsonValueKind.Null)
                dataJson = d.GetRawText();
            return new StreamEvent(@event, path, dataJson);
        }
        catch
        {
            return new StreamEvent(@event, "/", null);
        }
    }

    // MARK: Helpers

    private string RestUrl(string path, string token)
    {
        var clean = path.StartsWith('/') ? path[1..] : path;
        return $"{_config.DatabaseUrl}/{clean}.json?auth={token}";
    }

    private static void Check(HttpResponseMessage resp)
    {
        if (!resp.IsSuccessStatusCode) throw new RtdbException((int)resp.StatusCode);
    }

    /// A short human-shareable room code — the SAME alphabet as js/firebase.js so codes
    /// read identically everywhere (Crockford-ish, no confusable chars).
    public static string NewRoomCode()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var chars = new char[4];
        for (int i = 0; i < 4; i++) chars[i] = alphabet[Random.Shared.Next(alphabet.Length)];
        return new string(chars);
    }

    // Auth response DTOs
    private sealed record SignUpResponse(
        [property: JsonPropertyName("idToken")] string IdToken,
        [property: JsonPropertyName("refreshToken")] string RefreshToken,
        [property: JsonPropertyName("expiresIn")] string ExpiresIn,
        [property: JsonPropertyName("localId")] string LocalId);

    private sealed record RefreshResponse(
        [property: JsonPropertyName("id_token")] string IdToken,
        [property: JsonPropertyName("refresh_token")] string RefreshToken,
        [property: JsonPropertyName("expires_in")] string ExpiresIn,
        [property: JsonPropertyName("user_id")] string UserId);

    private sealed record IdpResponse(
        [property: JsonPropertyName("idToken")] string IdToken,
        [property: JsonPropertyName("refreshToken")] string RefreshToken,
        [property: JsonPropertyName("expiresIn")] string ExpiresIn,
        [property: JsonPropertyName("localId")] string LocalId,
        [property: JsonPropertyName("email")] string? Email,
        [property: JsonPropertyName("displayName")] string? DisplayName);
}
