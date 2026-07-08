using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// The host's SFX/stinger board (Wave B 3.30) — a set of named pads, each pointing
/// at a sound file the host chose (BYO clips: applause, buzzer, drumroll, airhorn…).
/// JSON-backed so a host's board persists between nights. The actual playback is
/// AvPlayer.PlaySfx; this is just the durable catalog.
public sealed record SfxPad
{
    [JsonPropertyName("label")] public string Label { get; init; } = "";
    [JsonPropertyName("path")] public string Path { get; init; } = "";
}

public sealed class SfxBoard
{
    private readonly string _file;
    private List<SfxPad> _pads = new();

    public SfxBoard(string file)
    {
        _file = file;
        try
        {
            if (System.IO.File.Exists(file))
                _pads = JsonSerializer.Deserialize<List<SfxPad>>(System.IO.File.ReadAllText(file)) ?? new();
        }
        catch { _pads = new(); }
    }

    public IReadOnlyList<SfxPad> Pads => _pads;

    /// Add a pad (label defaults to the file name; dedup by path; cap 24).
    public void Add(string path, string? label = null)
    {
        if (string.IsNullOrWhiteSpace(path) || _pads.Any(p => p.Path == path)) return;
        var name = string.IsNullOrWhiteSpace(label) ? DefaultLabel(path) : label!.Trim();
        _pads.Add(new SfxPad { Label = name, Path = path });
        if (_pads.Count > 24) _pads = _pads.Skip(_pads.Count - 24).ToList();
        Persist();
    }

    public void Remove(string path)
    {
        _pads.RemoveAll(p => p.Path == path);
        Persist();
    }

    /// Human label from a file path: the bare file name, no extension, spaced.
    public static string DefaultLabel(string path)
    {
        var name = System.IO.Path.GetFileNameWithoutExtension(path);
        return string.IsNullOrWhiteSpace(name) ? "Clip" : name.Replace('_', ' ').Replace('-', ' ').Trim();
    }

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_file);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_file, JsonSerializer.Serialize(_pads));
        }
        catch { /* best-effort */ }
    }
}
