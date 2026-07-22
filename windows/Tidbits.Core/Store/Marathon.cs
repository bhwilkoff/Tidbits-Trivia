using Tidbits.Core.Data;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Generates and resumes the Club-only Marathon run — a 200-question graded
/// endurance test whose value is measured mastery, not volume
/// (docs/CLUB-FEATURES-BUILD.md "Feature 3"). The load-bearing new mechanic is
/// **resume across sessions**: at most one `MarathonRun` exists at a time (held
/// in a single nullable slot on `RecordsStore`), its question ids are fixed at
/// creation from a stored seed (mirroring `DailyPick`'s deterministic
/// rank-and-slice), and every answer is persisted immediately so a crash/quit
/// never loses progress. Pure computation — `RecordsStore` owns the actual
/// read/write, same split as `WeakSpotArena`. Windows mirror of Apple's
/// `Marathon.swift` / Android's `Marathon.kt`.
public static class Marathon
{
    public const int DefaultLength = 200;

    /// TIDBITS_MARATHON_LEN=&lt;n&gt; shortens a run for testing (so one can be
    /// played to completion quickly, in a test or a screenshot pass). Production
    /// always sees 200 — this only ever narrows the count, never widens it.
    public static int RunLength
    {
        get
        {
            var raw = Environment.GetEnvironmentVariable("TIDBITS_MARATHON_LEN");
            return int.TryParse(raw, out var n) && n > 0 ? n : DefaultLength;
        }
    }

    /// The in-progress run, if any (at most one).
    public static MarathonRun? InProgress(RecordsStore records) => records.MarathonRun;

    /// Start a fresh run (discarding any stale in-progress one — `RecordsStore`
    /// holds a single slot, so overwriting it is automatic). The ids are drawn
    /// once from a fresh seed and fixed forever — a resume rebuilds the exact
    /// same set from the corpus.
    public static MarathonRun StartNew(RecordsStore records, CorpusDatabase corpus)
    {
        var seed = Guid.NewGuid().ToString();
        var allIds = corpus.OrderedIds("mixed");
        var count = Math.Min(RunLength, allIds.Count);
        var ids = PickIds(allIds, seed, count);
        var run = new MarathonRun(seed, ids);
        records.SaveMarathonRun(run);
        return run;
    }

    /// The remaining question ids for a run, from `CurrentIndex` to the end —
    /// what a resumed (or fresh) session actually loads into the engine. Pure —
    /// no corpus lookup — so it's unit-testable without a corpus fixture.
    public static IReadOnlyList<string> ResumeIds(MarathonRun run) =>
        run.QuestionIds.Skip(Math.Min(run.CurrentIndex, run.QuestionIds.Count)).ToList();

    /// Persist one answer immediately — called after every submit so a
    /// crash/quit never loses progress. The record captures everything the
    /// scorecard needs (category + difficulty + correctness) at answer-time, so
    /// deleting the app or the corpus changing later doesn't matter.
    public static void Record(RecordsStore records, MarathonRun run, AnsweredQuestion answer)
    {
        run.Append(new MarathonAnswerRecord
        {
            QuestionId = answer.Question.Id,
            CategoryId = answer.Question.CategoryId,
            Difficulty = answer.Question.Difficulty,
            Correct = answer.IsCorrect,
        });
        records.SaveMarathonRun(run);
    }

    /// The run just reached its true end — write the permanent `MarathonScore`
    /// and clear the in-progress run.
    public static MarathonScore Finish(RecordsStore records, MarathonRun run)
    {
        var results = run.Results;
        var correct = results.Count(r => r.Correct);
        // A plain difficulty-weighted score (10 pts x difficulty per correct
        // answer) — transparent by construction, no hidden model.
        var score = results.Where(r => r.Correct).Sum(r => r.Difficulty * 10);
        var duration = (DateTime.UtcNow - run.StartedAt).TotalSeconds;
        var domainBreakdown = ProgressMath.DomainIds.Select(d =>
        {
            var rows = results.Where(r => r.CategoryId == d).ToList();
            return new MarathonDomainStat(d, rows.Count(r => r.Correct), rows.Count);
        }).ToList();
        var entry = new MarathonScore
        {
            Score = score,
            Correct = correct,
            Total = results.Count,
            DurationSeconds = duration,
            DomainBreakdown = domainBreakdown,
        };
        records.FinishMarathon(entry);
        return entry;
    }

    /// Past completed runs, most recent first — the permanent Marathon history.
    public static IReadOnlyList<MarathonScore> History(RecordsStore records) => records.MarathonHistory;

    /// A genuine sample from the player's own history for the non-member pitch
    /// (MONETIZATION §4a: "a real preview, never a nag") — null once there's no
    /// completed run to sample. Unlike Weak-Spot/Story Archive, Marathon is
    /// Club-only end to end, so there's no free-tier data; the caller falls back
    /// to a static illustration line in that case.
    public static string? PreviewLine(RecordsStore records)
    {
        var last = records.MarathonHistory.FirstOrDefault();
        if (last is null) return null;
        return $"{(int)Math.Round(last.Accuracy * 100)}% on your last run — Club turns 200 questions into a measured map of what you know.";
    }

    /// Deterministic id pick from a seed — the same rank-and-slice `DailyPick`
    /// uses for the Daily, just keyed by a per-run seed instead of a calendar day.
    private static List<string> PickIds(IReadOnlyList<string> ids, string seed, int count) =>
        ids.Select(id => (id, rank: StableSeed.Of($"marathon:{seed}:{id}")))
           .OrderBy(t => t.rank)
           .ThenBy(t => t.id, Utf8Ordinal.Instance)
           .Take(count)
           .Select(t => t.id)
           .ToList();
}
