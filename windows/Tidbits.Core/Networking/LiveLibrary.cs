using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// One saved question: the host's own bank, kept across nights (LIVE-PACKAGE-
/// FORMAT §6). The Windows twin of the Mac `LibraryItem` / `LiveLibraryStore`.
public sealed record LibraryItem
{
    [JsonPropertyName("id")] public required string Id { get; init; }
    [JsonPropertyName("question")] public required Question Question { get; init; }
    [JsonPropertyName("savedAt")] public DateTimeOffset SavedAt { get; init; } = DateTimeOffset.UtcNow;
    [JsonPropertyName("source")] public string Source { get; init; } = "";

    public static string KeyFor(Question q) =>
        q.Prompt.Trim().ToLowerInvariant() + "|" + q.CorrectAnswer.ToLowerInvariant();
}

public static class LiveLibrary
{
    /// The search a picker runs: every space-separated term must appear in the
    /// prompt, an option, the explanation, a tag, the category or the source
    /// night; a category filter narrows first. Pure, so it is tested without a view.
    public static bool Matches(LibraryItem item, string query, string? category)
    {
        if (!string.IsNullOrEmpty(category) && item.Question.CategoryId != category) return false;
        var terms = (query ?? "").ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (terms.Length == 0) return true;
        var q = item.Question;
        var hay = string.Join(" ", new[] { q.Prompt, q.Explanation, q.CategoryId, item.Source }
            .Concat(q.Options).Concat(q.Tags).Concat(q.Accepted ?? Array.Empty<string>())).ToLowerInvariant();
        return terms.All(hay.Contains);
    }

    /// A library as a `bank` event: one round per category, in first-seen order,
    /// so a bank package opens on either host and reads as folders (§6.1).
    public static LiveEvent BankEvent(IReadOnlyList<LibraryItem> items, string name)
    {
        var order = new List<string>();
        var byCat = new Dictionary<string, List<Question>>();
        foreach (var it in items)
        {
            if (!byCat.ContainsKey(it.Question.CategoryId)) { order.Add(it.Question.CategoryId); byCat[it.Question.CategoryId] = new(); }
            byCat[it.Question.CategoryId].Add(it.Question);
        }
        return new LiveEvent
        {
            Name = name,
            Rounds = order.Select(c => new NightRound { Kind = GameMode.Classic, Count = byCat[c].Count }).ToList(),
            RoundQuestions = order.Select(c => (IReadOnlyList<Question>)byCat[c]).ToList(),
            RoundNotes = order.Select(_ => "").ToList(),
            RoundTimers = order.Select(_ => 0).ToList(),
        };
    }
}

public sealed class LiveLibraryStore
{
    private readonly string _path;
    private List<LibraryItem> _items = new();

    public LiveLibraryStore(string path)
    {
        _path = path;
        try
        {
            if (System.IO.File.Exists(path))
                _items = JsonSerializer.Deserialize<List<LibraryItem>>(System.IO.File.ReadAllText(path)) ?? new();
        }
        catch { _items = new(); }
    }

    public IReadOnlyList<LibraryItem> All => _items;

    /// Save (or refresh) a question. Returns true when it was NEW.
    public bool Add(Question q, string source)
    {
        var k = LibraryItem.KeyFor(q);
        var i = _items.FindIndex(it => LibraryItem.KeyFor(it.Question) == k);
        if (i >= 0)
        {
            _items[i] = _items[i] with { Question = q, SavedAt = DateTimeOffset.UtcNow, Source = source };
            Persist(); return false;
        }
        _items.Insert(0, new LibraryItem { Id = Guid.NewGuid().ToString("N"), Question = q, Source = source });
        Persist(); return true;
    }

    /// Save a whole round (or bank). Returns how many were new.
    public int Add(IEnumerable<Question> qs, string source) => qs.Count(q => Add(q, source));

    public void Remove(string id) { _items.RemoveAll(it => it.Id == id); Persist(); }

    public IReadOnlyList<LibraryItem> Search(string query, string? category = null) =>
        _items.Where(it => LiveLibrary.Matches(it, query, category)).ToList();

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(_items));
        }
        catch { /* best-effort */ }
    }
}
