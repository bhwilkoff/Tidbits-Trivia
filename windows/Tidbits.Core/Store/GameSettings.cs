using System.Text.Json;

namespace Tidbits.Core.Store;

/// Small persisted settings (port of GameSettings.swift's review-toggle KV).
/// JSON-file-backed, best-effort.
public sealed class GameSettings
{
    private readonly string _path;
    public bool ReviewEnabled { get; set; } = true;

    private sealed record Data(bool ReviewEnabled = true);

    public GameSettings(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path))
            {
                var d = JsonSerializer.Deserialize<Data>(File.ReadAllText(path));
                if (d is not null) ReviewEnabled = d.ReviewEnabled;
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
            File.WriteAllText(_path, JsonSerializer.Serialize(new Data(ReviewEnabled)));
        }
        catch { /* best-effort */ }
    }
}
