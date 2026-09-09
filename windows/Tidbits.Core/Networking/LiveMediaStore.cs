using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// Where a night's pictures and clips live once a package is imported —
/// content-addressed files under LocalAppData, plus one index that remembers
/// each file's kind, original name and https twin (LIVE-PACKAGE-FORMAT §5.1).
/// The Windows twin of the Mac `LiveMediaStore`; the event references media as
/// `tidbits-media:<id>` and this resolves it.
public static class LiveMediaStore
{
    public const string Scheme = "tidbits-media";

    public sealed record Info
    {
        [JsonPropertyName("ext")] public string Ext { get; init; } = "";
        [JsonPropertyName("mime")] public string Mime { get; init; } = "";
        [JsonPropertyName("kind")] public string Kind { get; init; } = "";
        [JsonPropertyName("bytes")] public int Bytes { get; init; }
        [JsonPropertyName("originalName")] public string? OriginalName { get; init; }
        [JsonPropertyName("sourceURL")] public string? SourceUrl { get; init; }
        [JsonPropertyName("credit")] public string? Credit { get; init; }
        [JsonPropertyName("license")] public string? License { get; init; }
    }

    /// §2.5 — the allow-list. A package is not a general-purpose archive.
    public static readonly IReadOnlyDictionary<string, (string Mime, string Kind)> Allowed =
        new Dictionary<string, (string, string)>
        {
            ["png"] = ("image/png", "image"), ["jpg"] = ("image/jpeg", "image"), ["jpeg"] = ("image/jpeg", "image"),
            ["gif"] = ("image/gif", "image"), ["webp"] = ("image/webp", "image"), ["svg"] = ("image/svg+xml", "image"),
            ["mp3"] = ("audio/mpeg", "audio"), ["m4a"] = ("audio/mp4", "audio"), ["wav"] = ("audio/wav", "audio"),
            ["aac"] = ("audio/aac", "audio"), ["ogg"] = ("audio/ogg", "audio"), ["flac"] = ("audio/flac", "audio"),
            ["mp4"] = ("video/mp4", "video"), ["mov"] = ("video/quicktime", "video"), ["m4v"] = ("video/x-m4v", "video"),
            ["webm"] = ("video/webm", "video"),
        };

    /// Overridable so tests (and the headless harness) keep their media out of the
    /// user's real store.
    public static string Directory { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tidbits", "LiveMedia");

    private static string IndexPath => Path.Combine(Directory, "index.json");
    private static readonly object Gate = new();

    public static string Sha256Hex(byte[] data)
    {
        var h = SHA256.HashData(data);
        return Convert.ToHexString(h).ToLowerInvariant();
    }
    public static string IdFor(byte[] data) => Sha256Hex(data)[..32];

    public static string NormalizedExt(string ext)
    {
        var e = ext.Trim().TrimStart('.').ToLowerInvariant();
        return e == "jpeg" ? "jpg" : e;
    }

    public static Dictionary<string, Info> LoadIndex()
    {
        try
        {
            if (!File.Exists(IndexPath)) return new();
            return JsonSerializer.Deserialize<Dictionary<string, Info>>(File.ReadAllText(IndexPath)) ?? new();
        }
        catch { return new(); }
    }

    private static void SaveIndex(Dictionary<string, Info> idx)
    {
        System.IO.Directory.CreateDirectory(Directory);
        File.WriteAllText(IndexPath, JsonSerializer.Serialize(idx, new JsonSerializerOptions { WriteIndented = true }));
    }

    /// Put bytes in the store; returns the id. Idempotent for identical bytes.
    public static string Store(byte[] data, string ext, string? originalName = null, string? sourceUrl = null,
                               string? credit = null, string? license = null)
    {
        var e = NormalizedExt(ext);
        if (!Allowed.TryGetValue(e, out var kind))
            throw new InvalidDataException($"{originalName ?? e} is not a picture, audio or video type Tidbits can carry.");
        var id = IdFor(data);
        lock (Gate)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var path = Path.Combine(Directory, $"{id}.{e}");
            if (!File.Exists(path)) File.WriteAllBytes(path, data);
            var idx = LoadIndex();
            var prev = idx.TryGetValue(id, out var p) ? p : new Info { Ext = e, Mime = kind.Mime, Kind = kind.Kind, Bytes = data.Length };
            idx[id] = prev with
            {
                OriginalName = originalName ?? prev.OriginalName,
                SourceUrl = sourceUrl ?? prev.SourceUrl,
                Credit = credit ?? prev.Credit,
                License = license ?? prev.License,
            };
            SaveIndex(idx);
        }
        return id;
    }

    public static string Reference(string id) => $"{Scheme}:{id}";

    public static string? IdFrom(string? url)
    {
        if (string.IsNullOrEmpty(url) || !url.StartsWith(Scheme + ":", StringComparison.Ordinal)) return null;
        var id = url[(Scheme.Length + 1)..].Trim('/');
        return id.Length == 0 ? null : id;
    }

    /// The file behind an id, if the store has it.
    public static string? FilePath(string id)
    {
        var idx = LoadIndex();
        if (idx.TryGetValue(id, out var info))
        {
            var p = Path.Combine(Directory, $"{id}.{info.Ext}");
            if (File.Exists(p)) return p;
        }
        if (!System.IO.Directory.Exists(Directory)) return null;
        foreach (var f in System.IO.Directory.EnumerateFiles(Directory, id + ".*")) return f;
        return null;
    }

    /// `tidbits-media:<id>` → the local file path; any other URL → itself.
    public static string? Resolve(string? url)
    {
        var id = IdFrom(url);
        return id is null ? url : FilePath(id);
    }

    /// The App installs this: a store file path → a small `data:image/jpeg;base64,…`
    /// (downscaled for venue Wi-Fi). Core has no image codec, and a null provider
    /// means a store-only picture is projector-only, which is the truthful result.
    public static Func<string, string?>? DataUrlProvider { get; set; }
    /// (path, maxSide, maxBytes) → JPEG bytes. Installed by the app (SkiaSharp);
    /// Core has no codec. The node/fallback split below is built on it.
    public static Func<string, int, int, byte[]?>? JpegProvider { get; set; }

    /// Decision 060 (pictures): the https twin, or the picture split into a
    /// once-written room NODE (the full ≤800 px JPEG) plus a SMALL data-URL
    /// fallback (≤320 px, ~20 KB) that rides in `imageURL`. Measured 2026-09-09:
    /// the full data URL made `pub` 108 KB, re-sent on every state change.
    public sealed record PublishablePicture(string? Fallback, LiveRoom.RoomMedia? Node, string? Id, LiveRoom.Media? Wire);
    public const int NodeThresholdBytes = 30_000;
    public const int PublishMaxPixels = 800, PublishMaxBytes = 120_000;
    public const int FallbackMaxPixels = 320, FallbackMaxBytes = 20_000;
    private static readonly Dictionary<string, PublishablePicture> PictureCache = new();

    public static PublishablePicture PublishPicture(string? url)
    {
        var id = IdFrom(url);
        if (id is null) return new(url, null, null, null);
        var idx = LoadIndex();
        if (idx.TryGetValue(id, out var info) && info.SourceUrl is { } s && s.StartsWith("http")) return new(s, null, null, null);
        lock (Gate)
        {
            if (PictureCache.TryGetValue(id, out var hit)) return hit;
            var path = FilePath(id);
            var full = path is null ? null : JpegProvider?.Invoke(path, PublishMaxPixels, PublishMaxBytes);
            PublishablePicture outp;
            if (full is null) outp = new(null, null, null, null);
            else if (full.Length <= NodeThresholdBytes) outp = new("data:image/jpeg;base64," + Convert.ToBase64String(full), null, null, null);
            else
            {
                var small = JpegProvider?.Invoke(path!, FallbackMaxPixels, FallbackMaxBytes) ?? full;
                var nodeId = IdFor(full);
                var name = info?.OriginalName is { } on ? System.IO.Path.GetFileNameWithoutExtension(on) : null;
                outp = new("data:image/jpeg;base64," + Convert.ToBase64String(small),
                           new LiveRoom.RoomMedia { Kind = "image", Mime = "image/jpeg", Bytes = full.Length, B64 = Convert.ToBase64String(full) },
                           nodeId,
                           new LiveRoom.Media { Kind = "image", Url = $"{LiveRoom.MediaScheme}:{nodeId}", Mime = "image/jpeg", Name = name, Bytes = full.Length });
            }
            PictureCache[id] = outp;
            return outp;
        }
    }
    private static readonly Dictionary<string, string> DataUrlCache = new();

    /// What a JOINER may be given (§5.3): the https twin when there is one,
    /// otherwise the picture itself as a small data URL. A phone can never open
    /// the host's package, and the shipped joiners load whatever `imageURL` says.
    public static string? PublishableUrl(string? url)
    {
        var id = IdFrom(url);
        if (id is null) return url;
        var idx = LoadIndex();
        if (idx.TryGetValue(id, out var info) && info.SourceUrl is { } s && s.StartsWith("http")) return s;
        lock (Gate)
        {
            if (DataUrlCache.TryGetValue(id, out var hit)) return hit;
            var path = FilePath(id);
            var made = path is null ? null : DataUrlProvider?.Invoke(path);
            if (made is not null) DataUrlCache[id] = made;
            return made;
        }
    }
}
