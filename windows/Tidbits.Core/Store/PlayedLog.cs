using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Store;

/// What a room has already been asked (macOS-DESIGN A2.6 → WINDOWS-PARITY 3.56).
/// A saved night is meant to be re-run next week, and re-run verbatim it asks the
/// same questions to the same regulars. The log remembers every question a HOSTED
/// night showed (not what the builder pulled), when, and which night — so the
/// builder can name a repeat and the corpus draw can skip it. Mirrors Swift's
/// LivePlayedLog.
public sealed record PlayedEntry
{
    [JsonPropertyName("at")] public DateTimeOffset At { get; init; }
    [JsonPropertyName("night")] public string Night { get; init; } = "";
}

public sealed class PlayedLog
{
    public const int Cap = 9000;
    private readonly string _path;
    private Dictionary<string, PlayedEntry> _entries = new();

    public static readonly Lazy<PlayedLog> Shared = new(() => new PlayedLog(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "live-played.json")));

    public PlayedLog(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
                _entries = JsonSerializer.Deserialize<Dictionary<string, PlayedEntry>>(File.ReadAllText(path)) ?? new();
        }
        catch { _entries = new(); }
    }

    public IReadOnlySet<string> Ids => _entries.Keys.ToHashSet();
    public PlayedEntry? Entry(string id) => _entries.GetValueOrDefault(id);

    /// The night showed these questions. Re-asking moves the date forward (the
    /// LAST time is what a host wants to know). Capped like the seen set.
    public void Record(IEnumerable<string> ids, string night, DateTimeOffset? at = null)
    {
        var when = at ?? DateTimeOffset.Now;
        foreach (var id in ids.Where(i => !string.IsNullOrEmpty(i))) _entries[id] = new PlayedEntry { At = when, Night = night };
        if (_entries.Count > Cap) _entries.Clear();
        Persist();
    }

    public void Clear() { _entries.Clear(); Persist(); }

    /// "Asked 6 days ago · Friday Pub Quiz" — the badge under a repeat.
    public static string AskedLine(PlayedEntry e, DateTimeOffset now)
    {
        var days = Math.Max(0, (int)Math.Floor((now - e.At).TotalDays));
        var when = days switch
        {
            0 => "today",
            1 => "yesterday",
            <= 13 => $"{days} days ago",
            <= 59 => $"{days / 7} weeks ago",
            _ => e.At.ToString("MMM d"),
        };
        var n = e.Night.Trim();
        return n.Length == 0 ? $"Asked {when}" : $"Asked {when} · {n}";
    }

    private void Persist()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_entries));
        }
        catch { /* best-effort */ }
    }
}
