using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Networking;

namespace Tidbits.Core.Store;

/// A night the host actually ran, kept after the cockpit closes (macOS-DESIGN
/// A2.12 → WINDOWS-PARITY 3.76). A night used to exist only while it was
/// happening: close the cockpit and the standings, the answer sheet and the
/// A3.11 report were gone. A pub host runs the same room every week and is asked
/// "who won last time?", so the night is archived on the machine that ran it (no
/// backend, nothing leaves the host). Mirrors Swift's `LiveNightArchive`.
public sealed record ArchivedNight
{
    public sealed record Row
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("score")] public int Score { get; init; }
        [JsonPropertyName("paper")] public bool Paper { get; init; }
    }

    [JsonPropertyName("id")] public string Id { get; init; } = "";
    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("venue")] public string Venue { get; init; } = "";
    [JsonPropertyName("endedAt")] public DateTimeOffset EndedAt { get; init; }
    [JsonPropertyName("standings")] public IReadOnlyList<Row> Standings { get; init; } = new List<Row>();
    [JsonPropertyName("log")] public IReadOnlyList<LiveAnswerRecord> Log { get; init; } = new List<LiveAnswerRecord>();

    /// The night read back (A3.11) — recomputed from the sheet rather than stored, so
    /// an archived night and a live one can never disagree.
    [JsonIgnore] public LiveNightReport Report => LiveNightReport.From(Log, Standings.Count);
    /// The top team, but only if it actually scored: a night where nobody was paid has no
    /// winner, and crowning whoever sorted first is a lie the host has to explain.
    [JsonIgnore] public Row? Winner => Standings.Count > 0 && Standings[0].Score > 0 ? Standings[0] : null;

    /// "3 teams · The Quizzards won with 14" — the card's one line.
    [JsonIgnore]
    public string Headline
    {
        get
        {
            if (Standings.Count == 0) return "No teams were scored";
            var teams = Standings.Count == 1 ? "1 team" : $"{Standings.Count} teams";
            return Winner is { } w ? $"{teams} · {w.Name} won with {w.Score}" : $"{teams} · nobody scored";
        }
    }
}

public sealed class NightArchive
{
    /// Twenty nights is about five months of a weekly room; past that a host is looking
    /// for a season, not last week.
    public const int Cap = 20;
    /// A single night's sheet is bounded too: 40 questions x 12 tables is already past
    /// what any pub runs, and a runaway log must not evict the whole archive.
    public const int LogCap = 600;

    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    private readonly string _path;
    private List<ArchivedNight> _nights = new();

    public static readonly Lazy<NightArchive> Shared = new(() => new NightArchive(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "live-nights.json")));

    public NightArchive(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
                _nights = JsonSerializer.Deserialize<List<ArchivedNight>>(File.ReadAllText(path), Json) ?? new();
        }
        catch { _nights = new(); }
    }

    /// Newest first.
    public IReadOnlyList<ArchivedNight> Nights => _nights;

    public ArchivedNight Record(string name, string venue, IReadOnlyList<ArchivedNight.Row> standings,
                               IReadOnlyList<LiveAnswerRecord> log, DateTimeOffset? at = null, string? id = null)
    {
        var night = new ArchivedNight
        {
            Id = id ?? Guid.NewGuid().ToString("N"),
            Name = name,
            Venue = venue,
            EndedAt = at ?? DateTimeOffset.Now,
            Standings = standings.ToList(),
            Log = log.Take(LogCap).ToList(),
        };
        _nights.Insert(0, night);
        if (_nights.Count > Cap) _nights = _nights.Take(Cap).ToList();
        Persist();
        return night;
    }

    public void Delete(string id)
    {
        _nights.RemoveAll(n => n.Id == id);
        Persist();
    }

    public void Clear()
    {
        _nights.Clear();
        Persist();
    }

    private void Persist()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_nights, Json));
        }
        catch { /* best-effort: an archive that cannot be written must not break the night */ }
    }
}
