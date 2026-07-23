using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Expedition store (docs/CLUB-FEATURES-BUILD.md "Feature 5") — pure and
/// UI-agnostic. NOT a new game engine: `StartStage` filters the bundled corpus by
/// category + a difficulty band (never-empty); `RecordStageResult` advances on pass,
/// leaves progress untouched on fail, and the LAST stage passing writes a permanent
/// certificate and retires the in-progress row — mirroring Marathon's finish, but
/// keyed per-expedition (several concurrent) rather than a single slot. Apple's
/// Expeditions.swift is canonical; Windows is the last of six platforms.
/// (No TIDBITS_CLUB env-var use here, so no "EnvSensitive" collection is needed —
/// only `DebugHooks.ExpeditionForcePass`, a plain settable bool this class's own
/// constructor resets before every test.)
public class ExpeditionsTests
{
    private static (string path, RecordsStore store) NewStore(RecordsData? data = null)
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-expedition-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(data ?? new RecordsData()));
        return (path, new RecordsStore(path));
    }

    private static CorpusDatabase Corpus() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures")).Corpus;

    public ExpeditionsTests() => DebugHooks.ExpeditionForcePass = false; // never leak between tests

    [Fact]
    public void All_has_the_same_three_campaigns_seven_stages_each_by_difficulty_band()
    {
        Assert.Equal(3, Expeditions.All.Count);
        var ids = Expeditions.All.Select(e => e.Id).ToList();
        Assert.Equal(new[] { "20th-century", "around-the-world", "scientific-record" }, ids);

        foreach (var expedition in Expeditions.All)
        {
            Assert.Equal(7, expedition.Stages.Count);
            Assert.Equal(Enumerable.Range(0, 7), expedition.Stages.Select(s => s.Index));
            foreach (var stage in expedition.Stages)
            {
                Assert.Equal(expedition.Domain, stage.CategoryId); // real category ids, not sub-domains
                Assert.Equal(10, stage.QuestionCount);
                Assert.Equal(6, stage.PassBar);
                Assert.InRange(stage.DifficultyLow, 1, 5);
                Assert.InRange(stage.DifficultyHigh, stage.DifficultyLow, 5);
            }
        }
    }

    [Fact]
    public void Named_finds_a_catalog_expedition_by_id_or_returns_null()
    {
        Assert.Equal("The 20th Century", Expeditions.Named("20th-century")!.Title);
        Assert.Null(Expeditions.Named("not-a-real-id"));
    }

    [Fact]
    public void Available_pairs_every_catalog_expedition_with_its_progress_row_or_null()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;
        Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 8, total: 10);

        var available = Expeditions.Available(records);
        Assert.Equal(3, available.Count);
        var started = available.First(a => a.Expedition.Id == "20th-century");
        Assert.NotNull(started.Progress);
        Assert.Equal(1, started.Progress!.CurrentStageIndex);
        var untouched = available.First(a => a.Expedition.Id == "around-the-world");
        Assert.Null(untouched.Progress);
    }

    [Fact]
    public void StartStage_filters_the_corpus_by_category_and_the_stage_difficulty_band()
    {
        var corpus = Corpus();
        var expedition = Expeditions.Named("scientific-record")!;
        var stage = expedition.Stages[0]; // science, difficulty 1-2
        var questions = Expeditions.StartStage(corpus, expedition, stage.Index);

        Assert.Equal(stage.QuestionCount, questions.Count);
        Assert.All(questions, q => Assert.Equal("science", q.CategoryId));
        Assert.All(questions, q => Assert.InRange(q.Difficulty, stage.DifficultyLow, stage.DifficultyHigh));
    }

    [Fact]
    public void StartStage_relaxes_to_the_whole_category_pool_when_the_band_is_too_thin()
    {
        // A synthetic corpus where the band (4-5) is thin but the category has plenty
        // of easier questions — the never-empty guarantee should still return a full
        // question set drawn from the whole category, not a starved band.
        var questions = Enumerable.Range(0, 20)
            .Select(i => new Question
            {
                Id = $"q{i}", Prompt = $"Prompt {i}", Options = new[] { "A", "B", "C", "D" },
                CorrectIndex = 0, CategoryId = "history", Difficulty = 1, Explanation = "Because.",
            })
            .Append(new Question // exactly one question actually in the 4-5 band
            {
                Id = "hard", Prompt = "Hard one", Options = new[] { "A", "B", "C", "D" },
                CorrectIndex = 0, CategoryId = "history", Difficulty = 5, Explanation = "Because.",
            })
            .ToList();
        var corpus = new CorpusDatabase(questions);
        var expedition = Expeditions.Named("20th-century")!;
        var stage = expedition.Stages[6]; // difficulty 4-5, questionCount 10

        var picked = Expeditions.StartStage(corpus, expedition, stage.Index);

        Assert.Equal(stage.QuestionCount, picked.Count); // never-empty: still a full round
    }

    [Fact]
    public void StartStage_returns_empty_for_an_unknown_stage_index()
    {
        var corpus = Corpus();
        var expedition = Expeditions.Named("20th-century")!;
        Assert.Empty(Expeditions.StartStage(corpus, expedition, stageIndex: 99));
    }

    [Fact]
    public void RecordStageResult_a_pass_advances_current_stage_index_and_persists()
    {
        var (path, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;

        var (passed, cert) = Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 7, total: 10);

        Assert.True(passed);
        Assert.Null(cert); // not the final stage
        var progress = Expeditions.Progress(records, expedition.Id);
        Assert.NotNull(progress);
        Assert.Equal(1, progress!.CurrentStageIndex);
        Assert.Single(progress.StageResults);
        Assert.True(progress.StageResults[0].Passed);
        Assert.Equal(7, progress.StageResults[0].Correct);

        // Persisted immediately — a fresh RecordsStore over the same file sees it.
        var reloaded = new RecordsStore(path);
        Assert.Equal(1, reloaded.ExpeditionProgress[expedition.Id].CurrentStageIndex);
    }

    [Fact]
    public void RecordStageResult_a_fail_never_advances_the_stage_the_player_stays_on()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;

        var (passed, cert) = Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 3, total: 10);

        Assert.False(passed);
        Assert.Null(cert);
        var progress = Expeditions.Progress(records, expedition.Id);
        Assert.NotNull(progress);
        Assert.Equal(0, progress!.CurrentStageIndex); // stays on stage 0 -- "try again"
        Assert.Single(progress.StageResults);
        Assert.False(progress.StageResults[0].Passed);
    }

    [Fact]
    public void RecordStageResult_a_retry_replaces_the_prior_attempt_for_that_stage_not_append()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;

        Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 2, total: 10); // fail
        Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 8, total: 10); // pass on retry

        var progress = Expeditions.Progress(records, expedition.Id)!;
        Assert.Single(progress.StageResults); // replaced, not appended
        Assert.True(progress.StageResults[0].Passed);
        Assert.Equal(1, progress.CurrentStageIndex);
    }

    [Fact]
    public void RecordStageResult_the_last_stage_passing_writes_a_certificate_and_deletes_progress()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("scientific-record")!; // 7 stages, index 0..6

        for (int i = 0; i < expedition.Stages.Count - 1; i++)
            Expeditions.RecordStageResult(records, expedition, stageIndex: i, correct: 8, total: 10);
        Assert.NotNull(Expeditions.Progress(records, expedition.Id)); // still in progress before the final stage

        var (passed, cert) = Expeditions.RecordStageResult(
            records, expedition, stageIndex: expedition.Stages.Count - 1, correct: 9, total: 10);

        Assert.True(passed);
        Assert.NotNull(cert);
        Assert.Equal(expedition.Id, cert!.ExpeditionId);
        Assert.Equal(expedition.Domain, cert.Domain);
        Assert.Equal(expedition.Stages.Count, cert.StagesCompleted);
        Assert.Equal(8 * 6 + 9, cert.TotalScore); // 6 stages at 8 correct + the final stage's 9

        Assert.Null(Expeditions.Progress(records, expedition.Id)); // the in-progress row is retired
        Assert.Single(records.ExpeditionCertificates);
        Assert.Same(cert, records.ExpeditionCertificates[0]);
    }

    [Fact]
    public void Multiple_expeditions_can_be_in_progress_at_once_independently()
    {
        var (_, records) = NewStore();
        var a = Expeditions.Named("20th-century")!;
        var b = Expeditions.Named("around-the-world")!;

        Expeditions.RecordStageResult(records, a, stageIndex: 0, correct: 8, total: 10); // pass
        Expeditions.RecordStageResult(records, b, stageIndex: 0, correct: 2, total: 10); // fail

        Assert.Equal(1, Expeditions.Progress(records, a.Id)!.CurrentStageIndex);
        Assert.Equal(0, Expeditions.Progress(records, b.Id)!.CurrentStageIndex);
        Assert.Equal(2, records.ExpeditionProgress.Count);
    }

    [Fact]
    public void ExpeditionForcePass_records_a_pass_regardless_of_score()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;
        try
        {
            DebugHooks.ExpeditionForcePass = true;
            var (passed, _) = Expeditions.RecordStageResult(records, expedition, stageIndex: 0, correct: 0, total: 10);
            Assert.True(passed);
        }
        finally { DebugHooks.ExpeditionForcePass = false; }
    }

    [Fact]
    public void Certificates_returns_completed_expeditions_most_recent_first()
    {
        var (_, records) = NewStore();
        var a = Expeditions.Named("20th-century")!;
        var b = Expeditions.Named("around-the-world")!;

        void Complete(Expedition e)
        {
            for (int i = 0; i < e.Stages.Count; i++)
                Expeditions.RecordStageResult(records, e, stageIndex: i, correct: 8, total: 10);
        }
        Complete(a);
        System.Threading.Thread.Sleep(5);
        Complete(b);

        var certs = Expeditions.Certificates(records);
        Assert.Equal(2, certs.Count);
        Assert.Equal(b.Id, certs[0].ExpeditionId); // most recent first
        Assert.Equal(a.Id, certs[1].ExpeditionId);
    }

    [Fact]
    public void PreviewLine_is_a_real_static_pitch_since_the_hub_is_a_preview_for_everyone()
    {
        var line = Expeditions.PreviewLine();
        Assert.False(string.IsNullOrWhiteSpace(line));
        Assert.Contains("expedition", line, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ResetAll_clears_expedition_progress_and_certificates()
    {
        var (_, records) = NewStore();
        var expedition = Expeditions.Named("20th-century")!;
        for (int i = 0; i < expedition.Stages.Count; i++)
            Expeditions.RecordStageResult(records, expedition, stageIndex: i, correct: 8, total: 10);
        Expeditions.RecordStageResult(records, Expeditions.Named("around-the-world")!, stageIndex: 0, correct: 3, total: 10);

        Assert.NotEmpty(records.ExpeditionCertificates);
        Assert.NotEmpty(records.ExpeditionProgress);

        records.ResetAll();

        Assert.Empty(records.ExpeditionCertificates);
        Assert.Empty(records.ExpeditionProgress);
    }
}
