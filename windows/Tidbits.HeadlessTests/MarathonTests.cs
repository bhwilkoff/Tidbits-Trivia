using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Data;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Marathon store (docs/CLUB-FEATURES-BUILD.md "Feature 3") — pure and
/// UI-agnostic. The load-bearing new mechanic is resume-across-sessions, so these
/// tests exercise exactly that: deterministic id pick from a seed, per-answer
/// persistence, resuming from `CurrentIndex`, and a Finish that writes the
/// permanent score, clears the run, and computes an honest per-domain breakdown.
/// Apple's Marathon.swift is canonical; Windows is the last of six platforms.
public class MarathonTests
{
    private static (string path, RecordsStore store) NewStore(RecordsData? data = null)
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-marathon-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(data ?? new RecordsData()));
        return (path, new RecordsStore(path));
    }

    private static CorpusDatabase Corpus() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures")).Corpus;

    private static Question Q(string id, string categoryId, int difficulty = 3) => new()
    {
        Id = id, Prompt = $"Prompt {id}", Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = 0, CategoryId = categoryId, Difficulty = difficulty, Explanation = "Because.",
    };

    private static AnsweredQuestion Answer(Question q, bool correct) => new()
    {
        Question = q, ChosenIndex = correct ? q.CorrectIndex : (q.CorrectIndex + 1) % q.Options.Count, SecondsTaken = 3,
    };

    [Fact]
    public void RunLength_defaults_to_200_and_TIDBITS_MARATHON_LEN_shortens_it()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_MARATHON_LEN");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", null);
            Assert.Equal(Marathon.DefaultLength, Marathon.RunLength);
            Assert.Equal(200, Marathon.RunLength);

            Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", "7");
            Assert.Equal(7, Marathon.RunLength);
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", previous); }
    }

    [Fact]
    public void StartNew_picks_a_fixed_ordered_set_deterministic_from_its_own_seed()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_MARATHON_LEN");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", "12");
            var corpus = Corpus();
            var (_, records) = NewStore();
            var run = Marathon.StartNew(records, corpus);

            Assert.Equal(12, run.QuestionIds.Count);
            Assert.Equal(12, run.QuestionIds.Distinct().Count()); // no dupes
            Assert.Equal(0, run.CurrentIndex);
            Assert.Empty(run.Results);

            // Re-deriving the SAME seed's rank-and-slice must reproduce the exact
            // same ids in the exact same order — the "resume rebuilds the same
            // set" guarantee this whole feature depends on.
            var allIds = corpus.OrderedIds("mixed");
            var rederived = allIds
                .Select(id => (id, rank: StableSeed.Of($"marathon:{run.Seed}:{id}")))
                .OrderBy(t => t.rank).ThenBy(t => t.id, Utf8Ordinal.Instance)
                .Take(12).Select(t => t.id).ToList();
            Assert.Equal(rederived, run.QuestionIds);
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", previous); }
    }

    [Fact]
    public void StartNew_persists_the_run_as_the_single_in_progress_slot_and_overwrites_a_stale_one()
    {
        var previous = Environment.GetEnvironmentVariable("TIDBITS_MARATHON_LEN");
        try
        {
            Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", "5");
            var (_, records) = NewStore();
            Assert.Null(Marathon.InProgress(records));

            var first = Marathon.StartNew(records, Corpus());
            Assert.Equal(first.Seed, Marathon.InProgress(records)!.Seed);

            // "Start over" is just StartNew again — the single slot is overwritten,
            // no separate delete step needed (unlike SwiftData's fetch-then-delete).
            var second = Marathon.StartNew(records, Corpus());
            Assert.NotEqual(first.Seed, second.Seed);
            Assert.Equal(second.Seed, Marathon.InProgress(records)!.Seed);
        }
        finally { Environment.SetEnvironmentVariable("TIDBITS_MARATHON_LEN", previous); }
    }

    [Fact]
    public void ResumeIds_returns_only_the_remaining_ids_from_CurrentIndex()
    {
        var run = new MarathonRun("seed", new[] { "a", "b", "c", "d" });
        Assert.Equal(new[] { "a", "b", "c", "d" }, Marathon.ResumeIds(run));

        run.CurrentIndex = 2;
        Assert.Equal(new[] { "c", "d" }, Marathon.ResumeIds(run));

        run.CurrentIndex = 4;
        Assert.Empty(Marathon.ResumeIds(run));

        run.CurrentIndex = 99; // defensive clamp — never past the end
        Assert.Empty(Marathon.ResumeIds(run));
    }

    [Fact]
    public void Record_appends_and_advances_CurrentIndex_and_persists_immediately()
    {
        var (path, records) = NewStore();
        var q1 = Q("q1", "history");
        var run = new MarathonRun("seed", new[] { "q1", "q2" });
        records.SaveMarathonRun(run);

        Marathon.Record(records, run, Answer(q1, correct: true));

        Assert.Equal(1, run.CurrentIndex);
        Assert.Single(run.Results);
        Assert.True(run.Results[0].Correct);
        Assert.Equal("history", run.Results[0].CategoryId);

        // Persisted immediately: a FRESH RecordsStore over the same file sees it —
        // a crash/quit right after this call loses nothing.
        var reloaded = new RecordsStore(path);
        Assert.NotNull(reloaded.MarathonRun);
        Assert.Equal(1, reloaded.MarathonRun!.CurrentIndex);
        Assert.Single(reloaded.MarathonRun.Results);
    }

    [Fact]
    public void Finish_writes_the_permanent_score_clears_the_run_and_computes_domain_breakdown()
    {
        var (_, records) = NewStore();
        var qHist = Q("h1", "history", difficulty: 3);
        var qSci = Q("s1", "science", difficulty: 4);
        var run = new MarathonRun("seed", new[] { "h1", "s1" });
        records.SaveMarathonRun(run);

        Marathon.Record(records, run, Answer(qHist, correct: true));
        Marathon.Record(records, run, Answer(qSci, correct: false));
        Assert.Equal(run.Total, run.CurrentIndex); // reached the true end

        var score = Marathon.Finish(records, run);

        Assert.Equal(1, score.Correct);
        Assert.Equal(2, score.Total);
        Assert.Equal(30, score.Score); // one correct at difficulty 3 -> 3 * 10, transparent by construction
        Assert.Null(records.MarathonRun); // the in-progress slot is cleared
        Assert.Single(records.MarathonHistory);
        Assert.Same(score, records.MarathonHistory[0]);

        var historyRow = score.DomainBreakdown.First(d => d.CategoryId == "history");
        Assert.Equal(1, historyRow.Correct);
        Assert.Equal(1, historyRow.Total);
        var scienceRow = score.DomainBreakdown.First(d => d.CategoryId == "science");
        Assert.Equal(0, scienceRow.Correct);
        Assert.Equal(1, scienceRow.Total);
        // Every other domain is present at 0/0 (ProgressMath.DomainIds is fixed) —
        // the caller filters those out before rendering.
        Assert.True(score.DomainBreakdown.Count >= 2);
    }

    [Fact]
    public void History_returns_completed_runs_most_recent_first()
    {
        var (_, records) = NewStore();
        var q = Q("q1", "history", difficulty: 1);

        var run1 = new MarathonRun("seed1", new[] { "q1" });
        records.SaveMarathonRun(run1);
        Marathon.Record(records, run1, Answer(q, correct: true));
        var first = Marathon.Finish(records, run1);

        var run2 = new MarathonRun("seed2", new[] { "q1" });
        records.SaveMarathonRun(run2);
        Marathon.Record(records, run2, Answer(q, correct: false));
        var second = Marathon.Finish(records, run2);

        var history = Marathon.History(records);
        Assert.Equal(2, history.Count);
        Assert.Same(second, history[0]);
        Assert.Same(first, history[1]);
    }

    [Fact]
    public void PreviewLine_reflects_the_last_completed_run_or_is_null_when_there_is_none()
    {
        var (_, records) = NewStore();
        Assert.Null(Marathon.PreviewLine(records)); // Club-only: no free-tier sample to fall back on

        var q = Q("q1", "history", difficulty: 1);
        var run = new MarathonRun("seed", new[] { "q1" });
        records.SaveMarathonRun(run);
        Marathon.Record(records, run, Answer(q, correct: true));
        Marathon.Finish(records, run);

        var line = Marathon.PreviewLine(records);
        Assert.NotNull(line);
        Assert.Contains("100%", line);
    }
}
