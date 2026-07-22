using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// Is this player a Tidbits Club member? The one gate every Club feature checks
/// (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §7). Windows twin of the Swift
/// EntitlementStore (TidbitsTrivia/Core/Networking/EntitlementStore.swift) and the
/// web (js/entitlement.js) / Android (Entitlement.kt) mirrors — same isClub gate, same
/// fail-open discipline.
///
/// Windows has no local store yet (Class A = Microsoft Store `StoreContext`, Phase 3), so —
/// exactly like the web/Kotlin mirrors — IsClub is purely the REMOTE read:
/// `entitlements/{accountKey}`, written by the Worker after a Merchant-of-Record purchase.
/// Requires a verified-email sign-in; the RTDB rule keys the read on `emailOwners/{key}`
/// matching the auth token email.
///
/// Fail OPEN: a transient read miss NEVER revokes Club (a paying member on a flaky
/// connection stays Club). Cache the last-known-good in a small JSON flag file (mirror of
/// `PlayerIdentityStore`'s path-based persistence) so a returning member is Club instantly,
/// before any network round-trip.
public sealed class EntitlementStore
{
    private readonly FirebaseRtdb _db;
    private readonly AccountIdentity _identity;
    private readonly string _cachePath;

    private sealed record Cache
    {
        [JsonPropertyName("isClub")] public bool IsClub { get; init; }
    }

    /// The gate. Seeded from the cached last-known-good so a returning member is Club
    /// instantly, before any network round-trip.
    public bool IsClub { get; private set; }

    public EntitlementStore(FirebaseRtdb db, AccountIdentity identity, string? cachePath = null)
    {
        _db = db;
        _identity = identity;
        _cachePath = cachePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TidbitsTrivia", "entitlement.json");
        IsClub = LoadCache();
    }

    /// Recompute Club status. Safe to call at launch, after sign-in, and after a purchase.
    /// Never throws; the worst case is "keep the cached answer".
    public async Task RefreshAsync()
    {
        if (!_identity.SignedIn || _identity.ProfileId is not { } key)
        {
            // Not signed in -> no remote entitlement is readable. Don't aggressively revoke
            // a cached true (fail open); it re-confirms on the next signed-in refresh. A
            // fresh anon session with no cache is simply not Club.
            return;
        }
        try
        {
            var ent = await _db.Get<Entitlement>(Entitlement.Path(key));
            Set(ent?.GrantsClub ?? false); // a clean read (incl. null -> not club) is authoritative
        }
        catch
        {
            // transient RTDB error -> keep the cached answer (fail open)
        }
    }

    /// Sign-out clears the cached Club state (the next person on this device isn't you).
    public void ClearOnSignOut() => Set(false);

    private void Set(bool club)
    {
        IsClub = club;
        SaveCache(club);
    }

    private bool LoadCache()
    {
        try
        {
            if (!File.Exists(_cachePath)) return false;
            var c = JsonSerializer.Deserialize<Cache>(File.ReadAllText(_cachePath));
            return c?.IsClub ?? false;
        }
        catch { return false; }
    }

    private void SaveCache(bool club)
    {
        try
        {
            var dir = Path.GetDirectoryName(_cachePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_cachePath, JsonSerializer.Serialize(new Cache { IsClub = club }));
        }
        catch { /* best-effort */ }
    }
}

/// The `entitlements/{sha256(email)}` wire record (MONETIZATION §7). Written ONLY by the
/// Worker; read-only for clients. Additive.
public sealed record Entitlement
{
    [JsonPropertyName("tier")] public string Tier { get; init; } = "";
    [JsonPropertyName("sources")] public IReadOnlyList<string>? Sources { get; init; }
    [JsonPropertyName("since")] public long? Since { get; init; }   // epoch ms
    [JsonPropertyName("until")] public long? Until { get; init; }   // epoch ms; null = lifetime / non-expiring
    [JsonPropertyName("ver")] public int? Ver { get; init; }

    public static string Path(string key) => $"entitlements/{key}";

    /// True when this record grants an active Club membership. A subscription past
    /// `Until` no longer grants; a lifetime (`Until == null`) always does.
    public bool GrantsClub =>
        Tier == "club" && (Until is not { } until || DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() < until);
}
