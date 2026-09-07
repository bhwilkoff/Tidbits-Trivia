using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// The Tidbits package (docs/LIVE-PACKAGE-FORMAT.md): a night with its media in
/// one `.tidbits` file. The Windows twin of the Mac `LivePackage`; the golden
/// `tools/live-event/golden.tidbits` proves both open the same bytes.
public static class LivePackage
{
    public const string FormatIdentifier = "com.learningischange.tidbits.package";
    public const int FormatVersion = 1;
    public const string Mimetype = "application/vnd.learningischange.tidbits+zip";
    public const string FileExtension = "tidbits";

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public sealed record MediaEntry
    {
        [JsonPropertyName("id")] public required string Id { get; init; }
        [JsonPropertyName("path")] public required string Path { get; init; }
        [JsonPropertyName("sha256")] public required string Sha256 { get; init; }
        [JsonPropertyName("bytes")] public int Bytes { get; init; }
        [JsonPropertyName("mime")] public string Mime { get; init; } = "";
        [JsonPropertyName("kind")] public string Kind { get; init; } = "";
        [JsonPropertyName("originalName")] public string? OriginalName { get; init; }
        [JsonPropertyName("sourceURL")] public string? SourceUrl { get; init; }
        [JsonPropertyName("credit")] public string? Credit { get; init; }
        [JsonPropertyName("license")] public string? License { get; init; }
    }

    public sealed record Manifest
    {
        [JsonPropertyName("format")] public string Format { get; init; } = FormatIdentifier;
        [JsonPropertyName("version")] public int Version { get; init; } = FormatVersion;
        [JsonPropertyName("kind")] public string Kind { get; init; } = "event";
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("createdAt")] public string CreatedAt { get; init; } = "";
        [JsonPropertyName("createdBy")] public string CreatedBy { get; init; } = "";
        [JsonPropertyName("media")] public IReadOnlyList<MediaEntry> Media { get; init; } = [];
    }

    public sealed record Contents(Manifest Manifest, LiveEventFile.Document Document, IReadOnlyDictionary<string, byte[]> Media);

    public sealed class PackageException(string message) : Exception(message);

    public static string SuggestedFileName(LiveEvent ev)
    {
        var name = string.IsNullOrWhiteSpace(ev.Name) ? "Tidbits Event" : ev.Name.Trim();
        foreach (var c in System.IO.Path.GetInvalidFileNameChars()) name = name.Replace(c, '-');
        return name + "." + FileExtension;
    }

    public static bool IsPackage(string path) =>
        string.Equals(System.IO.Path.GetExtension(path).TrimStart('.'), FileExtension, StringComparison.OrdinalIgnoreCase);

    // ---------------------------------------------------------------- read

    public static Contents Read(Stream stream)
    {
        ZipArchive zip;
        try { zip = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: true); }
        catch (InvalidDataException) { throw new PackageException("That file is not a Tidbits package."); }
        using (zip)
        {
            var mt = zip.GetEntry("mimetype");
            if (mt is null || ReadText(mt).Trim() != Mimetype) throw new PackageException("That file is not a Tidbits package.");
            var me = zip.GetEntry("manifest.json");
            var ee = zip.GetEntry("event.json");
            if (me is null || ee is null) throw new PackageException("That package is missing its manifest or event document.");
            Manifest? manifest;
            try { manifest = JsonSerializer.Deserialize<Manifest>(ReadText(me)); }
            catch (JsonException) { throw new PackageException("That file is not a Tidbits package."); }
            if (manifest is null || manifest.Format != FormatIdentifier) throw new PackageException("That file is not a Tidbits package.");
            if (manifest.Version > FormatVersion)
                throw new PackageException($"That package was saved by a newer version of Tidbits (format {manifest.Version}). Update Tidbits to open it.");
            LiveEventFile.Document doc;
            try { doc = LiveEventFile.Parse(ReadText(ee)); }
            catch (LiveEventFile.FileFormatException) { throw new PackageException("The package's event document is not a Tidbits Live event."); }

            var media = new Dictionary<string, byte[]>();
            foreach (var m in manifest.Media)
            {
                var entry = zip.GetEntry(m.Path)
                    ?? throw new PackageException($"The package is missing a media file it lists: {m.OriginalName ?? m.Path}.");
                using var s = entry.Open();
                using var ms = new MemoryStream();
                s.CopyTo(ms);
                var bytes = ms.ToArray();
                if (LiveMediaStore.Sha256Hex(bytes) != m.Sha256)
                    throw new PackageException($"A media file in the package does not match its checksum: {m.OriginalName ?? m.Path}.");
                media[m.Id] = bytes;
            }
            return new Contents(manifest, doc, media);
        }
    }

    private static string ReadText(ZipArchiveEntry e)
    {
        using var s = e.Open();
        using var r = new StreamReader(s, Encoding.UTF8);
        return r.ReadToEnd();
    }

    /// Open a package INTO the app: media into the store, clip ids into paths.
    public static (LiveEvent Event, IReadOnlyList<string> Problems) ImportIntoStore(Stream stream)
    {
        var c = Read(stream);
        var problems = new List<string>();
        foreach (var m in c.Manifest.Media)
        {
            if (!c.Media.TryGetValue(m.Id, out var bytes)) continue;
            try
            {
                LiveMediaStore.Store(bytes, System.IO.Path.GetExtension(m.Path), m.OriginalName, m.SourceUrl, m.Credit, m.License);
            }
            catch (Exception ex) { problems.Add(ex.Message); }
        }
        var ev = LiveEventFile.ToEvent(c.Document);
        // Clips: index-parallel media ids → store paths (§5.1). Audio and video share
        // the one RoundClips slot per question on Windows; video wins if both.
        var clips = new List<IReadOnlyList<string>>();
        bool any = false;
        for (int i = 0; i < c.Document.Event.Rounds.Count; i++)
        {
            var r = c.Document.Event.Rounds[i];
            var n = r.Questions.Count;
            var slots = new string[n];
            foreach (var (ids, kind) in new[] { (r.Audio, "audio"), (r.Video, "video") })
            {
                if (ids is null) continue;
                for (int q = 0; q < Math.Min(n, ids.Count); q++)
                {
                    var id = ids[q];
                    if (string.IsNullOrEmpty(id)) continue;
                    if (LiveMediaStore.IdFrom(id) is { } bare) id = bare;   // §3.2 bare id; prefix tolerated
                    var path = LiveMediaStore.FilePath(id);
                    if (path is null) { problems.Add($"{r.Title} {kind} #{q + 1}: media {id} is not in the package"); continue; }
                    slots[q] = path; any = true;
                }
            }
            clips.Add(slots.Select(s => s ?? "").ToList());
        }
        if (any) ev = ev with { RoundClips = clips };
        return (ev, problems);
    }

    // ---------------------------------------------------------------- write

    /// Build a package from an event: store pictures travel by id, clip paths are
    /// read, https pictures stay URLs (§3.3). Returns the clips that could NOT be read.
    public static IReadOnlyList<string> Write(Stream output, LiveEvent ev, string createdBy, string venue = "", string packageKind = "event")
    {
        var doc = LiveEventFile.BuildDocument(ev, venue);
        var media = new SortedDictionary<string, (byte[] Bytes, MediaEntry Entry)>(StringComparer.Ordinal);
        var dropped = new List<string>();
        var index = LiveMediaStore.LoadIndex();

        string? Add(byte[] bytes, string ext, string? originalName, string? sourceUrl, string? credit, string? license)
        {
            var e = LiveMediaStore.NormalizedExt(ext);
            if (!LiveMediaStore.Allowed.TryGetValue(e, out var kind)) return null;
            var sha = LiveMediaStore.Sha256Hex(bytes);
            var id = sha[..32];
            if (!media.ContainsKey(id))
                media[id] = (bytes, new MediaEntry
                {
                    Id = id, Path = $"media/{id}.{e}", Sha256 = sha, Bytes = bytes.Length, Mime = kind.Mime, Kind = kind.Kind,
                    OriginalName = originalName, SourceUrl = sourceUrl, Credit = credit, License = license,
                });
            return id;
        }
        string? AddStoreFile(string id)
        {
            var path = LiveMediaStore.FilePath(id);
            if (path is null) return null;
            index.TryGetValue(id, out var info);
            return Add(File.ReadAllBytes(path), System.IO.Path.GetExtension(path), info?.OriginalName, info?.SourceUrl, info?.Credit, info?.License);
        }

        var rounds = new List<LiveEventFile.PortableRound>();
        for (int i = 0; i < doc.Event.Rounds.Count; i++)
        {
            var r = doc.Event.Rounds[i];
            var qs = r.Questions.ToList();
            for (int q = 0; q < qs.Count; q++)
            {
                var id = LiveMediaStore.IdFrom(qs[q].ImageUrl);
                if (id is null) continue;
                if (AddStoreFile(id) is null)
                {
                    dropped.Add($"{r.Title} picture #{q + 1}");
                    qs[q] = qs[q] with { ImageUrl = null };
                }
            }
            // Windows keeps one clip slot per question (audio OR video), so the kind
            // is read off the file. Written into the array the kind belongs to.
            List<string?>? audio = null, video = null;
            for (int q = 0; q < qs.Count; q++)
            {
                var clip = ev.ClipFor(i, q);
                if (string.IsNullOrWhiteSpace(clip)) continue;
                if (!File.Exists(clip)) { dropped.Add($"{r.Title} clip #{q + 1} ({System.IO.Path.GetFileName(clip)})"); continue; }
                var ext = LiveMediaStore.NormalizedExt(System.IO.Path.GetExtension(clip));
                if (!LiveMediaStore.Allowed.TryGetValue(ext, out var kind)) { dropped.Add($"{r.Title} clip #{q + 1} ({System.IO.Path.GetFileName(clip)})"); continue; }
                var id = Add(File.ReadAllBytes(clip), ext, System.IO.Path.GetFileName(clip), null, null, null);
                if (kind.Kind == "video") { video ??= Enumerable.Repeat<string?>(null, qs.Count).ToList(); video[q] = id; }
                else { audio ??= Enumerable.Repeat<string?>(null, qs.Count).ToList(); audio[q] = id; }
            }
            rounds.Add(r with { Questions = qs, Audio = audio, Video = video });
        }
        doc = doc with { DroppedClipCount = dropped.Count, Event = doc.Event with { Rounds = rounds } };

        var manifest = new Manifest
        {
            Kind = packageKind,
            Title = ev.Name,
            CreatedAt = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"),
            CreatedBy = createdBy,
            Media = media.Values.Select(v => v.Entry).ToList(),
        };
        using var zip = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true);
        // §1.2: mimetype first, stored, so the file is sniffable.
        WriteEntry(zip, "mimetype", Encoding.ASCII.GetBytes(Mimetype), CompressionLevel.NoCompression);
        WriteEntry(zip, "manifest.json", Encoding.UTF8.GetBytes(JsonSerializer.Serialize(manifest, Options) + "\n"), CompressionLevel.Optimal);
        WriteEntry(zip, "event.json", Encoding.UTF8.GetBytes(LiveEventFile.Serialize(doc) + "\n"), CompressionLevel.Optimal);
        foreach (var (_, v) in media) WriteEntry(zip, v.Entry.Path, v.Bytes, CompressionLevel.NoCompression);
        return dropped;
    }

    private static void WriteEntry(ZipArchive zip, string name, byte[] bytes, CompressionLevel level)
    {
        var e = zip.CreateEntry(name, level);
        e.LastWriteTime = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        using var s = e.Open();
        s.Write(bytes, 0, bytes.Length);
    }
}
