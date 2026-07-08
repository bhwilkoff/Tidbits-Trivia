using System.Collections.Generic;
using System.Text.Json;

namespace Tidbits.Core.Store;

/// Per-day Daily results, first-completion-wins (Decision 036 / R-DAILY-1).
/// JSON-file-backed, best-effort. A day's result never changes once recorded, so
/// re-playing today can't overwrite it — the Daily is play-once.
public sealed class DailyLog
{
    private readonly string _path;
    private Dictionary<string, DailyResult> _byDay = new();

    public DailyLog(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
                _byDay = JsonSerializer.Deserialize<Dictionary<string, DailyResult>>(File.ReadAllText(path))
                         ?? new();
        }
        catch { _byDay = new(); }
    }

    public bool IsDone(string day) => _byDay.ContainsKey(day);
    public DailyResult? Result(string day) => _byDay.TryGetValue(day, out var r) ? r : null;

    /// Record a day's result once. A repeat call for the same day is ignored
    /// (first-completion-wins) so a replay can't inflate/deflate the record.
    public void Record(string day, int score, int correct, int total)
    {
        if (_byDay.ContainsKey(day)) return;
        _byDay[day] = new DailyResult(score, correct, total);
        Save();
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_byDay));
        }
        catch { /* best-effort */ }
    }
}

public sealed record DailyResult(int Score, int Correct, int Total);
