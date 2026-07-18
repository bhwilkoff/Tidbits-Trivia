using System.Text.Json;

namespace Tidbits.Core.Store;

/// Small persisted settings (port of GameSettings.swift's review-toggle KV).
/// JSON-file-backed, best-effort.
public sealed class GameSettings
{
    private readonly string _path;
    public bool ReviewEnabled { get; set; } = true;

    // Quick-Play memory (parity with web tidbits.lastMode/lastCat): the last single
    // mode + category played, so Quick Play replays it. Stored as strings to keep
    // this KV store free of the Models layer.
    public string? LastMode { get; set; }
    public string? LastCategoryId { get; set; }

    private sealed record Data(bool ReviewEnabled = true, string? LastMode = null, string? LastCategoryId = null);

    public GameSettings(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
            {
                var d = JsonSerializer.Deserialize<Data>(File.ReadAllText(path));
                if (d is not null)
                {
                    ReviewEnabled = d.ReviewEnabled;
                    LastMode = d.LastMode;
                    LastCategoryId = d.LastCategoryId;
                }
            }
        }
        catch { /* defaults */ }
    }

    public void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(new Data(ReviewEnabled, LastMode, LastCategoryId)));
        }
        catch { /* best-effort */ }
    }
}
