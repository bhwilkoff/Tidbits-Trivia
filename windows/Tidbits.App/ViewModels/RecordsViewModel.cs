using System;
using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.ViewModels;

/// The Records dashboard (R-REC-1) — pure derivations of the recorded games:
/// streak, lifetime, recent 3, per-domain knowledge, facts to review.
public sealed class RecordsViewModel
{
    public bool HasGames { get; }
    public bool NoGames => !HasGames;
    public int StreakCurrent { get; }
    public int StreakBest { get; }
    public int LifetimeGames { get; }
    public int LifetimeCorrect { get; }
    public int LifetimeAccuracy { get; } // percent
    public int TotalGames { get; }
    public bool HasMoreGames { get; }
    public IReadOnlyList<GameRow> RecentGames { get; }
    public IReadOnlyList<GameDetail> AllGames { get; }
    public IReadOnlyList<DomainRow> Domains { get; }
    public bool HasDomains => Domains.Count > 0;
    public IReadOnlyList<WedgeInfo> Wedges { get; }
    public int WedgesEarned { get; }
    public string PieCaption => WedgesEarned == 7 ? "All 7 domains mastered!" : $"{WedgesEarned} of 7 domains mastered";

    private static string WedgeHex(int i) => i switch
    {
        0 => "#FF5C35", 1 => "#2D5BFF", 2 => "#8B5CF6", 3 => "#2FCB8A", 4 => "#13B6C9", 5 => "#FF7A00", _ => "#888888"
    };
    public int ReviewCount { get; }
    public bool HasReview => ReviewCount > 0;
    public IReadOnlyList<BadgeRow> Badges { get; }
    public bool HasBadges => Badges.Count > 0;
    public IReadOnlyList<CalibrationRow> Calibration { get; }
    public bool HasCalibration => Calibration.Count > 0;

    public RecordsViewModel(RecordsStore store)
    {
        var games = store.Games.OrderByDescending(g => g.Date).ToList();
        HasGames = games.Count > 0;
        StreakCurrent = store.Streak.Current;
        StreakBest = store.Streak.Best;
        LifetimeGames = games.Count;
        TotalGames = games.Count;
        HasMoreGames = games.Count > 3;
        LifetimeCorrect = games.Sum(g => g.Correct);
        var answered = games.Sum(g => g.Total);
        LifetimeAccuracy = answered == 0 ? 0 : (int)Math.Round(100.0 * LifetimeCorrect / answered);

        RecentGames = games.Take(3).Select(g => new GameRow(
            g.Mode.Title(), TriviaCategory.Named(g.CategoryId).Name, g.Score, g.Correct, g.Total,
            g.Date.ToLocalTime().ToString("MMM d"))).ToList();

        AllGames = games.Select(g => new GameDetail(
            g.Mode.Title(), TriviaCategory.Named(g.CategoryId).Name, $"{g.Score} pts · {g.Correct}/{g.Total}",
            g.Date.ToLocalTime().ToString("MMM d, h:mm tt"),
            g.Answers.Select(a => new AnswerDot(a.Correct, a.Prompt, a.Answer)).ToList())).ToList();

        var domainProgress = DomainProgress.Summarize(games.Select(g => (g.CategoryId, g.Correct, g.Total)));

        // The Pie (breadth): one wedge per non-Mixed domain, filled when mastered.
        var wedgeById = domainProgress.ToDictionary(d => d.CategoryId, d => d.HasWedge);
        Wedges = TriviaCategory.All.Where(c => c.Id != "mixed")
            .Select(c => new WedgeInfo(c.Name, WedgeHex(c.ColorIndex), wedgeById.GetValueOrDefault(c.Id)))
            .ToList();
        WedgesEarned = Wedges.Count(w => w.Mastered);

        Domains = domainProgress
            .Where(d => d.Total > 0)
            .Select(d => new DomainRow(
                TriviaCategory.Named(d.CategoryId).Name, d.Level, d.LevelProgress,
                (int)Math.Round(d.Accuracy * 100), d.HasWedge)).ToList();

        ReviewCount = store.Missed.Count(m => !m.Resolved);

        // Stake calibration (F1) — per-confidence-tier hit rate, the self-knowledge mirror.
        Calibration = store.Calibration
            .Where(c => c.Total > 0)
            .Select(c => new CalibrationRow(
                c.TierValue switch { 3 => "Sure", 2 => "Likely", 1 => "Hunch", _ => $"Bet {c.TierValue}" },
                c.Hits, c.Total, (double)c.Hits / c.Total)).ToList();

        // Levelable badges — earned-only (hidden until the first tier is reached),
        // matching web/iOS. liveNights isn't tracked locally yet → 0 (Regular stays
        // hidden until it is), an honest gap not a false cell.
        int mastered = Domains.Count(d => d.Mastered);
        Badges = BadgeMath.Badges(LifetimeGames, StreakBest, mastered, LifetimeAccuracy, liveNights: 0)
            .Where(b => b.Tier >= 1)
            .Select(b => new BadgeRow(b.Name, b.Detail, b.Progress, b.Tier))
            .ToList();
    }
}

public sealed record BadgeRow(string Name, string Detail, double Progress, int Tier);

public sealed record WedgeInfo(string Name, string Hex, bool Mastered);

public sealed record CalibrationRow(string Label, int Hits, int Total, double Rate)
{
    public string Detail => $"{Hits}/{Total} · {(int)System.Math.Round(Rate * 100)}%";
}

public sealed record AnswerDot(bool Correct, string Prompt, string Answer);

public sealed record GameDetail(string Mode, string Category, string ScoreLine, string Date, IReadOnlyList<AnswerDot> Answers)
{
    public string Header => $"{Mode} · {Category}";
}

public sealed record GameRow(string Mode, string Category, int Score, int Correct, int Total, string Date)
{
    public string ScoreLine => $"{Score} pts · {Correct}/{Total}";
}

public sealed record DomainRow(string Name, int Level, double Progress, int Accuracy, bool Mastered)
{
    public string LevelLine => Mastered ? $"Level {Level} · mastered" : $"Level {Level} · {Accuracy}%";
}
