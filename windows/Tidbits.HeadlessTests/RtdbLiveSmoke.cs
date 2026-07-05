using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// LIVE smoke test against the real Firebase project (anon auth → put → get → delete).
/// Skipped unless TIDBITS_LIVE_SMOKE=1 (needs network + hits the live DB), so normal
/// `dotnet test` / CI stays offline-deterministic.
public class RtdbLiveSmoke
{
    [Fact]
    public async Task Anon_auth_put_get_delete_roundtrip()
    {
        if (Environment.GetEnvironmentVariable("TIDBITS_LIVE_SMOKE") != "1") return; // opt-in only

        var db = new FirebaseRtdb(tokens: new MemoryTokenStore());
        var uid = await db.EnsureAuth();
        Assert.False(string.IsNullOrEmpty(uid));

        var code = FirebaseRtdb.NewRoomCode();
        var path = $"{LiveRoom.Path("_smoke_" + code)}/meta";
        var meta = new LiveRoom.Meta { Host = uid, CreatedAt = 123, Name = "Smoke", Venue = "Test", State = "lobby" };

        await db.Put(path, meta);
        var back = await db.Get<LiveRoom.Meta>(path);
        Assert.NotNull(back);
        Assert.Equal("Smoke", back!.Name);
        Assert.Equal(uid, back.Host);

        await db.Delete(path);
        Assert.Null(await db.Get<LiveRoom.Meta>(path));
    }
}
