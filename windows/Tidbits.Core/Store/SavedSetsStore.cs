using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// A saved Create set — a labeled, replayable snapshot of generated questions.
public sealed record SavedSet
{
    [JsonPropertyName("id")] public string Id { get; init; } = Guid.NewGuid().ToString("N");
    [JsonPropertyName("label")] public string Label { get; init; } = "";
    [JsonPropertyName("questions")] public IReadOnlyList<Question> Questions { get; init; } = new List<Question>();

    [JsonIgnore] public int Count => Questions.Count;
}

/// Persisted Create sets (parity with web saved sets). JSON-file-backed,
/// best-effort, newest-first, capped.
public sealed class SavedSetsStore
{
    private readonly string _path;
    private List<SavedSet> _sets = new();
    private const int Cap = 30;

    public SavedSetsStore(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
                _sets = JsonSerializer.Deserialize<List<SavedSet>>(File.ReadAllText(path)) ?? new();
        }
        catch { _sets = new(); }
    }

    public IReadOnlyList<SavedSet> All => _sets;

    public SavedSet Add(string label, IReadOnlyList<Question> questions)
    {
        var set = new SavedSet { Label = label, Questions = questions.ToList() };
        _sets.Insert(0, set);
        if (_sets.Count > Cap) _sets = _sets.Take(Cap).ToList();
        Save();
        return set;
    }

    /// Drop everything. Used once by the quiz migration: leaving the legacy file in
    /// place would make every launch re-scan it, and a later write would resurrect
    /// the pre-contract format (docs/QUIZ-CONTRACT.md §7).
    public void Clear()
    {
        _sets.Clear();
        Save();
    }

    public void Remove(string id)
    {
        _sets.RemoveAll(s => s.Id == id);
        Save();
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_sets));
        }
        catch { /* best-effort */ }
    }
}
