namespace Tidbits.Core.Store;

/// Derived knowledge-cartography over game history — Topic Levels (depth) + The Pie
/// (breadth). Pure derivations of GameRecord aggregates (port of ProgressStats.swift);
/// every platform computes them identically from the same (category, correct, total) rows.
public static class ProgressMath
{
    public static readonly IReadOnlyList<string> DomainIds =
        new[] { "history", "science", "geography", "arts", "screen", "music", "sports", "business" };

    public const int WedgeCorrect = 15;
    public const double WedgeAccuracy = 0.60;

    /// Level L is reached at cumulative correct ≥ 5·L·(L+1)/2 (5, 15, 30, 50, 75, …).
    public static int Threshold(int level) => 5 * level * (level + 1) / 2;

    public static int Level(int correct)
    {
        int l = 0;
        while (Threshold(l + 1) <= correct) l++;
        return l;
    }

    public static double LevelProgress(int correct)
    {
        var l = Level(correct);
        int lo = Threshold(l), hi = Threshold(l + 1);
        return hi == lo ? 1 : Math.Min(1, Math.Max(0, (double)(correct - lo) / (hi - lo)));
    }
}

public sealed record DomainProgress(string CategoryId, int Correct, int Total)
{
    public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
    public int Level => ProgressMath.Level(Correct);
    public double LevelProgress => ProgressMath.LevelProgress(Correct);
    public int NextLevelCorrect => ProgressMath.Threshold(Level + 1);
    public bool HasWedge => Correct >= ProgressMath.WedgeCorrect && Accuracy >= ProgressMath.WedgeAccuracy;

    public static List<DomainProgress> Summarize(IEnumerable<(string CategoryId, int Correct, int Total)> rows)
    {
        var list = rows.ToList();
        return ProgressMath.DomainIds.Select(domain =>
        {
            var mine = list.Where(r => r.CategoryId == domain).ToList();
            return new DomainProgress(domain, mine.Sum(r => r.Correct), mine.Sum(r => r.Total));
        }).ToList();
    }

    public static int WedgesEarned(IEnumerable<DomainProgress> domains) => domains.Count(d => d.HasWedge);
}

/// One tiered achievement badge — levels up as the number grows (games, streak,
/// mastery, accuracy, live nights). Tiers match web + Android.
public sealed record LevelableBadge(string Name, int Value, IReadOnlyList<int> Tiers, string Unit)
{
    public int Tier => Tiers.Count(t => Value >= t);
    public int MaxTier => Tiers.Count;
    public int? Next => Tier < Tiers.Count ? Tiers[Tier] : null;

    public double Progress
    {
        get
        {
            if (Next is not { } n) return 1;
            var floor = Tier > 0 ? Tiers[Tier - 1] : 0;
            return Math.Min(1, Math.Max(0.06, (double)(Value - floor) / (n - floor)));
        }
    }

    public string Detail => Next is { } n ? $"{Value}/{n} {Unit} to Tier {Tier + 1}" : $"Maxed — {Value} {Unit}";
}

public static class BadgeMath
{
    public static List<LevelableBadge> Badges(int games, int longestStreak, int mastered, int lifetimeAccuracy, int liveNights) => new()
    {
        new("Scholar", games, new[] { 10, 50, 100, 500 }, "games"),
        new("On a Roll", longestStreak, new[] { 3, 7, 30, 100 }, "day streak"),
        new("Domain Master", mastered, new[] { 1, 3, 5, 7 }, "domains mastered"),
        new("Sharpshooter", games >= 5 ? lifetimeAccuracy : 0, new[] { 60, 75, 85, 95 }, "% accuracy"),
        new("Regular", liveNights, new[] { 1, 5, 15, 40 }, "live nights"),
    };
}
