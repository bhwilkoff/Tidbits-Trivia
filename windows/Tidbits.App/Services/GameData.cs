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

    private GameData(QuestionSources sources)
    {
        Sources = sources;
        Provider = new QuestionProvider(sources);
    }

    public static GameData FromDirectory(string dir) => new(QuestionSources.LoadFromDirectory(dir));

    /// The app's shared instance (reads the bundled Data/ dir on first use).
    public static readonly Lazy<GameData> Shared =
        new(() => FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data")));

    public GameEngine NewEngine() => new(Provider, Sources.Difficulty);
}
