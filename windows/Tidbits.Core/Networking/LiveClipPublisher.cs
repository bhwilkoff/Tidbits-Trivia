using System;
using System.Collections.Generic;
using System.IO;

namespace Tidbits.Core.Networking;

/// Decision 060 on Windows: turn a question's clip (a path — a store file or the
/// host's own file) into what the ROOM can be given. An https file link when the
/// store remembers one; otherwise the bytes of a web-safe file under the cap,
/// written once to `live/{code}/media/{id}`.
///
/// Windows has no transcoder in the box (the Mac re-encodes through
/// AVFoundation), so a clip travels AS IT IS: an MP3/M4A/AAC or MP4/M4V under
/// 3 MB reaches the phones; anything else is reported to the host as "not on
/// phones" and the room hears it from the PA. That delta is documented in
/// WINDOWS-PARITY 3.53.
public static class LiveClipPublisher
{
    public sealed record Prepared(LiveRoom.Media? Media, LiveRoom.RoomMedia? Node, string? Id, string Note);

    public static readonly IReadOnlyDictionary<string, string> WebSafeAudio = new Dictionary<string, string>
        { ["mp3"] = "audio/mpeg", ["m4a"] = "audio/mp4", ["aac"] = "audio/aac" };
    public static readonly IReadOnlyDictionary<string, string> WebSafeVideo = new Dictionary<string, string>
        { ["mp4"] = "video/mp4", ["m4v"] = "video/mp4" };

    private static readonly Dictionary<string, Prepared> Cache = new();
    private static readonly object Lock = new();

    public static string Megabytes(long n) => n >= 1_000_000 ? $"{n / 1_000_000.0:F1} MB" : $"{Math.Max(1, n / 1000)} KB";

    /// A link a `<video>` / player can open directly — a file, not a page.
    public static bool IsDirectFileLink(string? s)
    {
        if (string.IsNullOrWhiteSpace(s) || !(s.StartsWith("https://") || s.StartsWith("http://"))) return false;
        if (!Uri.TryCreate(s, UriKind.Absolute, out var u)) return false;
        var ext = LiveMediaStore.NormalizedExt(Path.GetExtension(u.AbsolutePath));
        return WebSafeAudio.ContainsKey(ext) || WebSafeVideo.ContainsKey(ext) || ext is "ogg" or "wav" or "webm" or "mov";
    }

    /// The clip's kind from its extension: "audio", "video", or null for neither.
    public static string? KindOf(string path)
    {
        var ext = LiveMediaStore.NormalizedExt(Path.GetExtension(path));
        return LiveMediaStore.Allowed.TryGetValue(ext, out var a) && a.Kind is "audio" or "video" ? a.Kind : null;
    }

    public static Prepared Prepare(string path)
    {
        var key = path;
        try { var fi = new FileInfo(path); key = $"{path}|{fi.Length}|{fi.LastWriteTimeUtc.Ticks}"; } catch { }
        lock (Lock) { if (Cache.TryGetValue(key, out var hit)) return hit; }
        var result = Build(path);
        lock (Lock) Cache[key] = result;
        return result;
    }

    private static Prepared Build(string path)
    {
        if (!File.Exists(path)) return new(null, null, null, "Not on phones — the clip could not be opened");
        var kind = KindOf(path);
        if (kind is null) return new(null, null, null, "Not on phones — not an audio or video file");
        var name = Path.GetFileNameWithoutExtension(path);

        // A store file remembers where it came from; a direct https file link is
        // the cheapest thing a phone can be given.
        var storeId = StoreIdOf(path);
        if (storeId is not null && LiveMediaStore.LoadIndex().TryGetValue(storeId, out var info))
        {
            if (!string.IsNullOrWhiteSpace(info.OriginalName)) name = Path.GetFileNameWithoutExtension(info.OriginalName);
            if (IsDirectFileLink(info.SourceUrl))
                return new(new LiveRoom.Media { Kind = kind, Url = info.SourceUrl!, Mime = info.Mime, Name = name, Bytes = info.Bytes },
                           null, null, "On phones by link");
        }

        var ext = LiveMediaStore.NormalizedExt(Path.GetExtension(path));
        var size = new FileInfo(path).Length;
        var safe = kind == "audio" ? WebSafeAudio : WebSafeVideo;
        if (!safe.TryGetValue(ext, out var mime))
            return new(null, null, null,
                $"Not on phones — Windows sends a clip as it is; attach an {(kind == "audio" ? "MP3 or M4A" : "MP4")} under {Megabytes(LiveRoom.MediaMaxBytes)}");
        if (size > LiveRoom.MediaMaxBytes)
            return new(null, null, null, $"Not on phones — too long to send ({Megabytes(size)}); the room hears it from the PA");
        var data = File.ReadAllBytes(path);
        var id = LiveMediaStore.IdFor(data);
        var node = new LiveRoom.RoomMedia { Kind = kind, Mime = mime, Bytes = data.Length, B64 = Convert.ToBase64String(data) };
        var media = new LiveRoom.Media { Kind = kind, Url = $"{LiveRoom.MediaScheme}:{id}", Mime = mime, Name = name, Bytes = data.Length };
        return new(media, node, id, $"On phones too · {Megabytes(data.Length)}");
    }

    /// The id of a file that lives in the media store (its name is `<id>.<ext>`).
    private static string? StoreIdOf(string path)
    {
        try
        {
            var dir = Path.GetFullPath(LiveMediaStore.Directory).TrimEnd(Path.DirectorySeparatorChar);
            if (!Path.GetFullPath(path).StartsWith(dir, StringComparison.OrdinalIgnoreCase)) return null;
            var stem = Path.GetFileNameWithoutExtension(path);
            return stem.Length == 32 ? stem : null;
        }
        catch { return null; }
    }
}
