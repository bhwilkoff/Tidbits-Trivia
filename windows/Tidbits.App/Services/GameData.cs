using System;
using System.IO;
using Tidbits.Core.Data;
using Tidbits.Core.Store;

namespace Tidbits.App.Services;

/// Loads the bundled question data once and hands out a shared QuestionProvider +
/// new GameEngines. Data/ is the shared assets JSONs, copied to output at build.
public sealed class GameData
{
    public QuestionSources Sources { get; }
    public QuestionProvider Provider { get; }
    public RecordsStore Records { get; }
    public GameSettings Settings { get; }

    private GameData(QuestionSources sources)
    {
        Sources = sources;
        Provider = new QuestionProvider(sources);
        var appDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia");
        Records = new RecordsStore(Path.Combine(appDir, "records.json"));
        Settings = new GameSettings(Path.Combine(appDir, "settings.json"));
    }

    public static GameData FromDirectory(string dir) => new(QuestionSources.LoadFromDirectory(dir));

    /// The app's shared instance (reads the bundled Data/ dir on first use).
    public static readonly Lazy<GameData> Shared =
        new(() => FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data")));

    public GameEngine NewEngine() => new(Provider, Sources.Difficulty);
}
