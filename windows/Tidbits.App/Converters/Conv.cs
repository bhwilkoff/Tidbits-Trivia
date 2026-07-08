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

    public static readonly FuncValueConverter<GameEngine.Phase, bool> IsRoundIntro =
        new(p => p == GameEngine.Phase.RoundIntro);

    /// The question surface shows only while playing or on reveal — NOT during
    /// the round interstitial (which has its own card).
    public static readonly FuncValueConverter<GameEngine.Phase, bool> IsQuestion =
        new(p => p == GameEngine.Phase.Playing || p == GameEngine.Phase.Reveal);

    public static readonly FuncValueConverter<GameEngine.Phase, bool> NotFinished =
        new(p => p != GameEngine.Phase.Finished && p != GameEngine.Phase.Idle && p != GameEngine.Phase.Loading);

    public static readonly FuncValueConverter<double, string> Seconds =
        new(s => $"{(int)System.Math.Ceiling(s)}s");

    /// True when a string is non-empty — used to hide the reveal "Answer:" line
    /// for shapes (ordering/matching) with no single answer string.
    public static readonly FuncValueConverter<string?, bool> NonEmpty =
        new(s => !string.IsNullOrWhiteSpace(s));
}
