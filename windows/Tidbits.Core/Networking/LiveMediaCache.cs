using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

namespace Tidbits.Core.Networking;

/// Decision 060: the joiner's copy of a clip the host offered in `pub.media`. A
/// `room:<id>` node is fetched ONCE into LocalAppData and kept by id; an https
/// link is handed back as it is. Nothing is fetched until asked.
public sealed class LiveMediaCache
{
    public static readonly LiveMediaCache Shared = new();
    private readonly FirebaseRtdb _db;
    private readonly Dictionary<string, string> _files = new();
    private readonly Dictionary<string, Task<string>> _inFlight = new();
    private readonly object _lock = new();
    public LiveMediaCache(FirebaseRtdb? db = null) => _db = db ?? new FirebaseRtdb();

    public static string Directory { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "LiveRoomMedia");

    /// The extension a player needs to recognise the container.
    public static string FileExtension(string mime, string kind) => mime.ToLowerInvariant() switch
    {
        "audio/mpeg" or "audio/mp3" => "mp3",
        "audio/mp4" or "audio/x-m4a" or "audio/m4a" => "m4a",
        "audio/aac" => "aac",
        "audio/wav" or "audio/x-wav" => "wav",
        "video/mp4" => "mp4",
        "video/quicktime" => "mov",
        "video/webm" => "webm",
        "image/jpeg" or "image/jpg" => "jpg",
        "image/png" => "png",
        "image/gif" => "gif",
        "image/webp" => "webp",
        _ => kind == "video" ? "mp4" : kind == "image" ? "jpg" : "m4a",
    };

    /// A path or URL a player can open for this offer.
    public Task<string> LocalPath(LiveRoom.Media media, string code)
    {
        var id = LiveRoom.MediaIdFrom(media.Url);
        if (id is null)
        {
            if (media.Url.StartsWith("http", StringComparison.OrdinalIgnoreCase)) return Task.FromResult(media.Url);
            throw new InvalidOperationException("That clip's link isn't valid.");
        }
        lock (_lock)
        {
            if (_files.TryGetValue(id, out var hit) && File.Exists(hit)) return Task.FromResult(hit);
            if (_inFlight.TryGetValue(id, out var running)) return running;
            var task = Fetch(id, code);
            _inFlight[id] = task;
            return task;
        }
    }

    private async Task<string> Fetch(string id, string code)
    {
        try
        {
            var node = await _db.Get<LiveRoom.RoomMedia>(LiveRoom.MediaPath(code, id))
                       ?? throw new InvalidOperationException("The host's clip isn't in the room yet.");
            var data = Convert.FromBase64String(node.B64);
            if (data.Length == 0) throw new InvalidOperationException("That clip couldn't be read.");
            System.IO.Directory.CreateDirectory(Directory);
            var path = Path.Combine(Directory, $"{id}.{FileExtension(node.Mime, node.Kind)}");
            await File.WriteAllBytesAsync(path, data);
            lock (_lock) _files[id] = path;
            return path;
        }
        finally { lock (_lock) _inFlight.Remove(id); }
    }
}
