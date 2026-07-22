using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Tidbits Club gate (Decision 047). Windows twin of the Swift/JS/Kotlin EntitlementStore
/// tests — pins `GrantsClub` (the wire-record rule) and the fail-open / last-known-good
/// caching contract. Windows is remote-only (no local store yet), so — like the web/Kotlin
/// mirrors — a signed-OUT refresh must never touch the network or revoke a cached answer;
/// that's the slice testable here without a live RTDB round-trip (see RtdbLiveSmoke for the
/// gated live path).
public class EntitlementStoreTests
{
    // MARK: - Entitlement.GrantsClub (the wire-record rule)

    [Fact]
    public void Club_with_no_until_grants_lifetime()
    {
        var ent = new Entitlement { Tier = "club" };
        Assert.True(ent.GrantsClub);
    }

    [Fact]
    public void Club_with_a_future_until_grants()
    {
        var future = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds();
        var ent = new Entitlement { Tier = "club", Until = future };
        Assert.True(ent.GrantsClub);
    }

    [Fact]
    public void Club_with_a_past_until_does_not_grant()
    {
        var past = DateTimeOffset.UtcNow.AddDays(-1).ToUnixTimeMilliseconds();
        var ent = new Entitlement { Tier = "club", Until = past };
        Assert.False(ent.GrantsClub);
    }

    [Fact]
    public void A_non_club_tier_does_not_grant()
    {
        var ent = new Entitlement { Tier = "free" };
        Assert.False(ent.GrantsClub);
    }

    [Fact]
    public void No_record_at_all_does_not_grant()
    {
        Entitlement? ent = null;
        Assert.False(ent?.GrantsClub ?? false);
    }

    // MARK: - Store: caching + fail-open

    private static string TempCachePath() =>
        Path.Combine(Path.GetTempPath(), $"tidbits-entitlement-{Guid.NewGuid():N}.json");

    private static AccountIdentity SignedOutAccount() =>
        new(new FirebaseRtdb(tokens: new MemoryTokenStore()), new MemoryTokenStore());

    private static EntitlementStore NewStore(string path, IStoreGateway? store = null) =>
        new(new FirebaseRtdb(tokens: new MemoryTokenStore()), SignedOutAccount(), store, cachePath: path);

    /// A fake local store (Class A) so the local-first / fail-open logic is testable off Windows.
    private sealed class FakeStore(bool? entitled) : IStoreGateway
    {
        public Task<bool?> IsClubEntitledAsync() => Task.FromResult(entitled);
        public Task<IReadOnlyList<StoreProductInfo>> GetProductsAsync() =>
            Task.FromResult<IReadOnlyList<StoreProductInfo>>(Array.Empty<StoreProductInfo>());
        public Task<StorePurchaseResult> PurchaseAsync(string productId) =>
            Task.FromResult(StorePurchaseResult.Unavailable);
    }

    [Fact]
    public async Task Local_store_YES_grants_club_without_any_network()
    {
        var path = TempCachePath();
        try
        {
            var store = NewStore(path, new FakeStore(true));   // Store says entitled
            await store.RefreshAsync();                          // signed out, no RTDB
            Assert.True(store.IsClub);                           // Class A alone grants Club
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Local_store_UNKNOWN_when_signed_out_keeps_cached_true_fail_open()
    {
        var path = TempCachePath();
        try
        {
            File.WriteAllText(path, "{\"isClub\":true}");        // returning member, cached
            var store = NewStore(path, new FakeStore(null));     // Store: unknown (fresh/unpackaged)
            await store.RefreshAsync();
            Assert.True(store.IsClub);                           // fail open — never revoke on unknown
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Local_store_clean_NO_while_signed_out_revokes()
    {
        var path = TempCachePath();
        try
        {
            File.WriteAllText(path, "{\"isClub\":true}");
            var store = NewStore(path, new FakeStore(false));    // Store: definitively not entitled
            await store.RefreshAsync();
            Assert.False(store.IsClub);                          // a clean negative lowers the gate
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void NoStoreGateway_reports_unknown_and_unavailable()
    {
        var g = new NoStoreGateway();
        Assert.Null(g.IsClubEntitledAsync().Result);             // unknown -> fail open
        Assert.Empty(g.GetProductsAsync().Result);
        Assert.Equal(StorePurchaseResult.Unavailable, g.PurchaseAsync("x").Result);
    }

    [Fact]
    public void A_fresh_store_with_no_cache_starts_not_club()
    {
        var path = TempCachePath();
        try
        {
            Assert.False(NewStore(path).IsClub);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void A_returning_member_is_club_instantly_from_the_cache_before_any_network_round_trip()
    {
        var path = TempCachePath();
        try
        {
            // Seed the cache the way a prior session's Set(true) would have written it.
            File.WriteAllText(path, """{"isClub":true}""");

            // A brand-new store instance (a fresh launch) reads the cached last-known-good
            // synchronously in its constructor — no RefreshAsync() call needed to be Club.
            Assert.True(NewStore(path).IsClub);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public async Task Refresh_while_signed_out_never_touches_the_network_and_keeps_a_cached_true_fail_open()
    {
        var path = TempCachePath();
        try
        {
            File.WriteAllText(path, """{"isClub":true}""");
            var store = NewStore(path);
            Assert.True(store.IsClub);

            // Not signed in -> no remote entitlement is readable. RefreshAsync must return
            // without reaching the network (a fresh AccountIdentity has never bootstrapped
            // auth) and must NOT revoke the cached true.
            await store.RefreshAsync();
            Assert.True(store.IsClub);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public async Task Refresh_while_signed_out_does_not_promote_a_cached_false()
    {
        var path = TempCachePath();
        try
        {
            var store = NewStore(path);
            Assert.False(store.IsClub);
            await store.RefreshAsync();
            Assert.False(store.IsClub); // still nothing to grant it, and nothing to fail open on
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void ClearOnSignOut_revokes_and_persists_false_for_the_next_session()
    {
        var path = TempCachePath();
        try
        {
            File.WriteAllText(path, """{"isClub":true}""");
            var store = NewStore(path);
            Assert.True(store.IsClub);

            store.ClearOnSignOut();
            Assert.False(store.IsClub);

            // Persisted -> the next person on this device isn't seeded as Club.
            Assert.False(NewStore(path).IsClub);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    // MARK: - TIDBITS_CLUB debug override (docs/CLUB-FEATURES-BUILD.md gating convention)

    [Fact]
    public void TIDBITS_CLUB_env_override_forces_the_gate_open_without_touching_the_cache()
    {
        var path = TempCachePath();
        var previous = Environment.GetEnvironmentVariable("TIDBITS_CLUB");
        try
        {
            var store = NewStore(path); // no cache -> ordinarily not Club
            Assert.False(store.IsClub);

            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "1");
            Assert.True(store.IsClub);            // pre-launch override opens every gate
            Assert.True(Tidbits.Core.Store.DebugHooks.ForceClub);

            Environment.SetEnvironmentVariable("TIDBITS_CLUB", "0");
            Assert.False(store.IsClub);            // only the literal "1" forces it open

            Environment.SetEnvironmentVariable("TIDBITS_CLUB", null);
            Assert.False(store.IsClub);            // unset -> a pure no-op, back to the real cache
        }
        finally
        {
            Environment.SetEnvironmentVariable("TIDBITS_CLUB", previous);
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
