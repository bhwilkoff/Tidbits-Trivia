using System.Runtime.InteropServices;
using Tidbits.App.Services;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Parity 1.22 — the Windows credential store. The refresh token is long-lived and
/// enough to assume a player's identity, so it must not sit on disk in cleartext.
/// Behaviour is asserted on every OS (via the file fallback); the ENCRYPTION itself
/// is asserted only on Windows, where DPAPI exists — windows-latest CI is the gate.
public class DpapiTokenStoreTest : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "tidbits-tok-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); } catch { }
    }

    private static bool OnWindows => RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

    [Fact]
    public void Round_trips_a_token()
    {
        var s = new DpapiTokenStore(_dir);
        s.Set("refresh", "secret-token-value");
        Assert.Equal("secret-token-value", s.Get("refresh"));
    }

    [Fact]
    public void A_missing_key_is_null_not_a_throw()
    {
        Assert.Null(new DpapiTokenStore(_dir).Get("nope"));
    }

    [Fact]
    public void Delete_removes_the_token()
    {
        var s = new DpapiTokenStore(_dir);
        s.Set("refresh", "v");
        s.Delete("refresh");
        Assert.Null(s.Get("refresh"));
    }

    [Fact]
    public void Survives_a_new_store_instance()
    {
        new DpapiTokenStore(_dir).Set("refresh", "persisted");
        Assert.Equal("persisted", new DpapiTokenStore(_dir).Get("refresh"));
    }

    [Fact]
    public void The_token_is_not_readable_as_cleartext_on_disk()
    {
        if (!OnWindows) return; // DPAPI is Windows-only; CI is the gate.

        var s = new DpapiTokenStore(_dir);
        s.Set("refresh", "super-secret-refresh");

        foreach (var f in Directory.GetFiles(_dir))
        {
            var bytes = File.ReadAllBytes(f);
            var asText = System.Text.Encoding.UTF8.GetString(bytes);
            Assert.DoesNotContain("super-secret-refresh", asText);
        }
    }

    [Fact]
    public void A_legacy_cleartext_token_is_migrated_and_the_plaintext_removed()
    {
        // Windows-only by construction: off Windows the fallback IS the file store, so
        // <key>.txt is the live store rather than legacy cleartext to migrate away from.
        if (!OnWindows) return;

        // A shipped build wrote <key>.txt in the clear. Upgrading must neither sign the
        // user out nor leave the cleartext behind.
        Directory.CreateDirectory(_dir);
        var legacy = Path.Combine(_dir, "refresh.txt");
        File.WriteAllText(legacy, "legacy-token");

        var s = new DpapiTokenStore(_dir);
        Assert.Equal("legacy-token", s.Get("refresh"));
        Assert.False(File.Exists(legacy), "the cleartext token must be removed after migration");
        // And it survives as the re-protected copy.
        Assert.Equal("legacy-token", new DpapiTokenStore(_dir).Get("refresh"));
    }

    [Fact]
    public void Undecryptable_ciphertext_does_not_wedge_sign_in()
    {
        if (!OnWindows) return;

        Directory.CreateDirectory(_dir);
        // Garbage where a DPAPI blob should be (a restored backup / roamed profile).
        File.WriteAllBytes(Path.Combine(_dir, "refresh.dpapi"), new byte[] { 1, 2, 3, 4, 5 });

        var s = new DpapiTokenStore(_dir);
        Assert.Null(s.Get("refresh"));       // drops it rather than throwing
        s.Set("refresh", "fresh");           // and re-authentication still works
        Assert.Equal("fresh", s.Get("refresh"));
    }
}
