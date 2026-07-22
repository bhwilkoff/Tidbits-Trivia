using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Feature 4 — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md). A transparent,
/// interpreted layer over the SAME per-game rows the free Topic Levels / Pie
/// already read (`GameRecord.CategoryId`/`Correct`/`Total`, `ProgressMath.DomainIds`)
/// — additive, never a lock on what's already free (R-MON-1). PURE DERIVATION, no
/// new persistence: `GameRecord.Date` has carried a per-game timestamp since the
/// original write path, so no schema change is needed here (confirmed true of the
/// Android port too — Windows is the last of six platforms). No opaque "mastery
/// score": every number below is a plain count. Windows mirror of Apple's
/// `KnowledgeAtlas.swift` / Android's `KnowledgeAtlas.kt`.
///
/// `AnswerDetail` (the per-question record inside a `GameRecord`) carries no
/// timestamp of its own, so month-bucketing uses each GAME's date for all of
/// that game's answers — the same granularity the corpus already persists.
/// Trailing 12 months only; older history keeps feeding the free lifetime
/// Pie/Levels but drops out of the Atlas's month math.
public static class KnowledgeAtlas
{
    /// Below this many answers in a window, a read is withheld rather than
    /// shown noisy — "don't flag a domain with <8 answers" (design spec).
    public const int SampleFloor = 8;
    /// A domain counts as "strong" in the decay radar's older window at this
    /// accuracy or higher.
    public const double StrongThreshold = 0.70;
    /// A drop of at least this many accuracy points (0..1 scale) counts as
    /// decaying, both for the per-domain trajectory flag and the radar.
    public const double DecayDelta = 0.12;

    /// One domain's trailing-12-month standing. `RecentAccuracy`/`PriorAccuracy`
    /// are this-quarter (months 0-2) vs the quarter before (months 3-5); either
    /// is null below `SampleFloor` — an honest "not enough history yet" rather
    /// than a noisy arrow.
    public sealed record DomainAtlasEntry(string CategoryId, int Correct, int Total, double? RecentAccuracy, double? PriorAccuracy)
    {
        public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
        public int SampleSize => Total;
        /// Recent-quarter minus prior-quarter accuracy, in points (0..1 scale).
        /// Null when either quarter is too thin to read.
        public double? TrajectoryDelta => RecentAccuracy is { } r && PriorAccuracy is { } p ? r - p : null;
        public bool IsDecaying => (TrajectoryDelta ?? 0) <= -DecayDelta;
    }

    /// A domain that was strong 6+ months ago and has since declined — the
    /// Decay radar's "shore it up" list.
    public sealed record DecayEntry(string CategoryId, double PastAccuracy, double RecentAccuracy)
    {
        public double Delta => RecentAccuracy - PastAccuracy;
    }

    private sealed record Row(string CategoryId, int Correct, int Total, int MonthsAgo);

    /// Per-domain trailing-12-month standing, domains never played omitted (same
    /// convention as `ProgressMath`/`DomainProgress` for the free Pie/Levels).
    public static List<DomainAtlasEntry> Domains(IReadOnlyList<GameRecord> games)
    {
        var rows = TrailingYearRows(games);
        var result = new List<DomainAtlasEntry>();
        foreach (var domain in ProgressMath.DomainIds)
        {
            var mine = rows.Where(r => r.CategoryId == domain).ToList();
            if (mine.Count == 0) continue;
            result.Add(new DomainAtlasEntry(
                domain, mine.Sum(r => r.Correct), mine.Sum(r => r.Total),
                RecentAccuracy: QuarterAccuracy(mine, 0, 2),
                PriorAccuracy: QuarterAccuracy(mine, 3, 5)));
        }
        return result.OrderByDescending(d => d.Total).ToList();
    }

    /// Domains strong (>=`StrongThreshold`) 6-11 months ago that have since
    /// dropped by >=`DecayDelta` in the last 6 months — both windows honest
    /// about sample size.
    public static List<DecayEntry> DecayRadar(IReadOnlyList<GameRecord> games)
    {
        var rows = TrailingYearRows(games);
        var result = new List<DecayEntry>();
        foreach (var domain in ProgressMath.DomainIds)
        {
            var mine = rows.Where(r => r.CategoryId == domain).ToList();
            if (QuarterAccuracy(mine, 6, 11) is not { } past) continue;
            if (QuarterAccuracy(mine, 0, 5) is not { } recent) continue;
            if (past < StrongThreshold || recent > past - DecayDelta) continue;
            result.Add(new DecayEntry(domain, past, recent));
        }
        return result.OrderBy(d => d.Delta).ToList();
    }

    /// A genuine strongest + weakest domain for the non-member teaser
    /// (MONETIZATION §4a: "a real preview, never a nag"). Null until the
    /// player has enough history for at least one honest read.
    public static string? PreviewLine(IReadOnlyList<GameRecord> games)
    {
        var ds = Domains(games).Where(d => d.Total >= 3).OrderBy(d => d.Accuracy).ToList();
        if (ds.Count == 0) return null;
        var weakest = ds[0];
        var weakName = TriviaCategory.Named(weakest.CategoryId).Name;
        var strongest = ds[^1];
        if (strongest.CategoryId == weakest.CategoryId)
        {
            return $"{(int)Math.Round(weakest.Accuracy * 100)}% in {weakName} so far — Club maps every domain across 12 months and shows what's rising or drifting.";
        }
        var strongName = TriviaCategory.Named(strongest.CategoryId).Name;
        return $"{(int)Math.Round(strongest.Accuracy * 100)}% in {strongName}, {(int)Math.Round(weakest.Accuracy * 100)}% in {weakName} — Club maps everything you know and where it's drifting.";
    }

    // MARK: - Month bucketing

    private static List<Row> TrailingYearRows(IReadOnlyList<GameRecord> games)
    {
        var cutoff = DateTime.UtcNow.AddMonths(-12);
        return games.Where(g => g.Date >= cutoff)
            .Select(g => new Row(g.CategoryId, g.Correct, g.Total, MonthsAgo(g.Date)))
            .ToList();
    }

    private static double? QuarterAccuracy(IReadOnlyList<Row> rows, int lo, int hi)
    {
        var mine = rows.Where(r => r.MonthsAgo >= lo && r.MonthsAgo <= hi).ToList();
        var total = mine.Sum(r => r.Total);
        if (total < SampleFloor) return null;
        var correct = mine.Sum(r => r.Correct);
        return (double)correct / total;
    }

    private static int MonthsAgo(DateTime date, DateTime? now = null)
    {
        var today = now ?? DateTime.UtcNow;
        var months = (today.Year - date.Year) * 12 + (today.Month - date.Month);
        return Math.Max(0, months);
    }
}
