using System;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// The local player profile façade (portable-identity spine, 1.17) — a display
/// name + a deterministic avatar seed, persisted locally. Rename + avatar re-roll
/// are the self-expression verbs (monetization-safe, no pay-to-win). Sync/sign-in
/// layer on top later; this is the local-first base.
public sealed class PlayerIdentityStore
{
    private readonly string _path;
    private Profile _profile = Profile.Default();

    public sealed record Profile
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "Player";
        [JsonPropertyName("avatarSeed")] public string AvatarSeed { get; init; } = "";

        [JsonIgnore] public double AvatarHue => PlayerIdentity.AvatarHue(AvatarSeed);

        public static Profile Default() => new() { Name = "Player", AvatarSeed = NewSeed() };
    }

    public PlayerIdentityStore(string path)
    {
        _path = path;
        try
        {
            if (System.IO.File.Exists(path))
                _profile = JsonSerializer.Deserialize<Profile>(System.IO.File.ReadAllText(path)) ?? Profile.Default();
            else Persist();
        }
        catch { _profile = Profile.Default(); }
    }

    public Profile Current => _profile;

    /// Rename (trimmed, capped at 24 chars; empty is ignored).
    public void Rename(string name)
    {
        var t = (name ?? "").Trim();
        if (t.Length == 0) return;
        _profile = _profile with { Name = t.Length > 24 ? t[..24] : t };
        Persist();
    }

    /// Re-roll the avatar — a fresh deterministic hue. Self-expression, not pay-to-win.
    public void RerollAvatar()
    {
        _profile = _profile with { AvatarSeed = NewSeed() };
        Persist();
    }

    private static string NewSeed() => Guid.NewGuid().ToString("N")[..12];

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(_profile));
        }
        catch { /* best-effort */ }
    }
}
