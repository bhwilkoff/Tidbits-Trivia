using Avalonia.Data.Converters;
using Tidbits.Core.Store;

namespace Tidbits.App.Converters;

/// Small binding converters for the game surface (phase → visibility, etc.).
public static class Conv
{
    public static readonly FuncValueConverter<GameEngine.Phase, bool> IsPlaying =
        new(p => p == GameEngine.Phase.Playing);

    public static readonly FuncValueConverter<GameEngine.Phase, bool> IsReveal =
        new(p => p == GameEngine.Phase.Reveal);

    public static readonly FuncValueConverter<GameEngine.Phase, bool> IsFinished =
        new(p => p == GameEngine.Phase.Finished);

    public static readonly FuncValueConverter<GameEngine.Phase, bool> NotFinished =
        new(p => p != GameEngine.Phase.Finished && p != GameEngine.Phase.Idle && p != GameEngine.Phase.Loading);

    public static readonly FuncValueConverter<double, string> Seconds =
        new(s => $"{(int)System.Math.Ceiling(s)}s");
}
