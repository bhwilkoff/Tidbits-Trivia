using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// A saved Custom Mix preset ("My Mix") — a named set of modes + a category,
/// replayed via GameEngine.StartMix. Parity with the web/Mac presets.
public sealed record GamePreset
{
    [JsonPropertyName("id")] public string Id { get; init; } = Guid.NewGuid().ToString("N");
    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("modes")] public IReadOnlyList<GameMode> Modes { get; init; } = new List<GameMode>();
    [JsonPropertyName("categoryId")] public string CategoryId { get; init; } = "mixed";
}

/// Persisted game presets (parity with web tidbits.presets / Mac GamePreset).
/// JSON-file-backed, best-effort, newest-first, upsert-by-name, capped at 5.
public sealed class PresetsStore
{
    private readonly string _path;
    private List<GamePreset> _presets = new();
    private const int Cap = 5;

    private static readonly JsonSerializerOptions Opts =
        new() { Converters = { new JsonStringEnumConverter() } };

    public PresetsStore(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
                _presets = JsonSerializer.Deserialize<List<GamePreset>>(File.ReadAllText(path), Opts) ?? new();
        }
        catch { _presets = new(); }
    }

    public IReadOnlyList<GamePreset> All => _presets;

    /// Upsert by name (case-insensitive), newest-first, capped — matches web savePreset.
    public GamePreset Save(string name, IReadOnlyList<GameMode> modes, string categoryId)
    {
        _presets.RemoveAll(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
        var preset = new GamePreset { Name = name.Trim(), Modes = modes.ToList(), CategoryId = categoryId };
        _presets.Insert(0, preset);
        if (_presets.Count > Cap) _presets = _presets.Take(Cap).ToList();
        Persist();
        return preset;
    }

    public void Remove(string id)
    {
        _presets.RemoveAll(p => p.Id == id);
        Persist();
    }

    private void Persist()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_presets, Opts));
        }
        catch { /* best-effort */ }
    }
}
