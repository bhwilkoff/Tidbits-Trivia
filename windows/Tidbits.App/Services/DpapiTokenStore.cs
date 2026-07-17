using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Tidbits.Core.Networking;

namespace Tidbits.App.Services;

/// The Windows twin of the Apple Keychain store (parity 1.22). Rides the existing
/// ITokenStore seam, so `Tidbits.Core` stays OS-agnostic — Core only knows the
/// interface, and this Windows-only implementation is injected by the app.
///
/// Why this matters: FileTokenStore writes the Firebase REFRESH token to
/// LocalApplicationData in cleartext. That token is long-lived and is enough to
/// assume the player's identity (records, Elo, standings), so it should not sit on
/// disk in the clear. DPAPI with CurrentUser scope binds the ciphertext to the
/// Windows user account — another user on the same box cannot read it, and it is
/// useless if copied to a different machine.
///
/// DPAPI is Windows-only: off Windows this falls back to the plain file store so the
/// macOS dev head and headless tests keep working.
public sealed class DpapiTokenStore : ITokenStore
{
    private readonly string _dir;
    private readonly ITokenStore? _fallback;

    /// Extra entropy — DPAPI mixes this in, so another app running as the same user
    /// cannot decrypt these blobs just by calling Unprotect on the file.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("TidbitsTrivia.tokens.v1");

    public DpapiTokenStore(string? dir = null)
    {
        _dir = dir ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TidbitsTrivia", "tokens");
        _fallback = OperatingSystem.IsWindows() ? null : new FileTokenStore(_dir);
    }

    private string PathFor(string key) => Path.Combine(_dir, key + ".dpapi");

    public string? Get(string key)
    {
        if (_fallback is { } f) return f.Get(key);
        try
        {
            var p = PathFor(key);
            if (!File.Exists(p)) return MigrateLegacy(key);
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(p), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            // Ciphertext from another user/machine (roamed profile, restored backup) is
            // undecryptable. Drop it and re-authenticate rather than wedging sign-in.
            Delete(key);
            return null;
        }
        catch { return null; }
    }

    public void Set(string key, string value)
    {
        if (_fallback is { } f) { f.Set(key, value); return; }
        try
        {
            Directory.CreateDirectory(_dir);
            var blob = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(value), Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(PathFor(key), blob);
        }
        catch { }
    }

    public void Delete(string key)
    {
        if (_fallback is { } f) { f.Delete(key); return; }
        try { var p = PathFor(key); if (File.Exists(p)) File.Delete(p); } catch { }
        DeleteLegacy(key);
    }

    private string LegacyPathFor(string key) => Path.Combine(_dir, key + ".txt");

    /// A build that already shipped FileTokenStore left a cleartext token on disk.
    /// Read it once, re-protect it, and remove the plaintext — so upgrading users are
    /// not silently signed out AND stop carrying a cleartext credential.
    private string? MigrateLegacy(string key)
    {
        try
        {
            var legacy = LegacyPathFor(key);
            if (!File.Exists(legacy)) return null;
            var value = File.ReadAllText(legacy);
            Set(key, value);
            File.Delete(legacy);
            return value;
        }
        catch { return null; }
    }

    private void DeleteLegacy(string key)
    {
        try { var p = LegacyPathFor(key); if (File.Exists(p)) File.Delete(p); } catch { }
    }
}
