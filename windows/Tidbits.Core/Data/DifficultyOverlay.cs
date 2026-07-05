using System.Text.Json;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// F3 derived-difficulty overlay (Wikipedia pageviews → 1..5 per subject), from
/// the shared difficulty.json. Additive — the corpus is untouched; Ladder mode
/// sorts + weights scoring by it. A subject not in the map (or a live-generated
/// question) defaults to 3. Port of Core/Data/DifficultyOverlay.swift.
public sealed class DifficultyOverlay
{
    private readonly Dictionary<string, int> _map;

    public DifficultyOverlay(Dictionary<string, int>? map = null) => _map = map ?? new();

    public static DifficultyOverlay Load(Stream json)
    {
        using var doc = JsonDocument.Parse(json);
        var map = new Dictionary<string, int>();
        if (doc.RootElement.TryGetProperty("difficulty", out var d) && d.ValueKind == JsonValueKind.Object)
            foreach (var p in d.EnumerateObject())
                if (p.Value.TryGetInt32(out var v)) map[p.Name] = v;
        return new DifficultyOverlay(map);
    }

    /// 1 (best-known) … 5 (obscure). Keyed by the underscored Wikipedia title.
    public int DifficultyForTitle(string title) => _map.GetValueOrDefault(title.Replace(' ', '_'), 3);

    public int DifficultyFor(Question q) => DifficultyForTitle(q.SourceTitle);
}
