using Tidbits.Core.Data;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Generates and tracks Club Expeditions — multi-week structured campaigns through a
/// single domain (docs/CLUB-FEATURES-BUILD.md "Feature 5"). NOT a new game engine:
/// every stage routes into the EXISTING `.classic` launch path via a category +
/// difficulty-band filtered question set drawn fresh from the bundled corpus. Unlike
/// Marathon's at-most-one run, several expeditions may be in progress at once — each
/// tracked by its own `ExpeditionProgress` row, keyed by `Expedition.Id` in a
/// dictionary on `RecordsStore`. Windows mirror of Apple's `Expeditions.swift`
/// (Core/Store) / Android's `Expeditions.kt` (data/Expeditions.kt).
public static class Expeditions
{
    /// Start with 2-3 hand-defined campaigns (design spec) — the SAME 3 as
    /// Apple/web/Android, 7 stages each, differing by DIFFICULTY BAND (the taxonomy
    /// is flat). The shape allows adding more without any client change.
    public static readonly IReadOnlyList<Expedition> All = new[]
    {
        new Expedition("20th-century", "The 20th Century",
            "A hundred years, decade by decade — from the Great War to the dot-com boom.",
            "history", "scroll", new[]
            {
                new ExpeditionStage(0, "Turn of the Century", "Where it all began — the basics of a hundred years.", "history", 1, 2),
                new ExpeditionStage(1, "The Great Wars", "Two wars that reshaped the century.", "history", 1, 3),
                new ExpeditionStage(2, "The Cold War Era", "A world split in two.", "history", 2, 3),
                new ExpeditionStage(3, "Movements & Milestones", "Civil rights, independence, revolutions.", "history", 2, 4),
                new ExpeditionStage(4, "Leaders & Turning Points", "The decisions that moved history.", "history", 3, 4),
                new ExpeditionStage(5, "The Wider Century", "Everything else the timeline holds.", "history", 3, 5),
                new ExpeditionStage(6, "The Historian's Final Exam", "The century's hardest corners.", "history", 4, 5),
            }),
        new Expedition("around-the-world", "Around the World",
            "A geography trek from the basics of the map to its far corners.",
            "geography", "globe", new[]
            {
                new ExpeditionStage(0, "The Basics of the Map", "Continents, oceans, and the big picture.", "geography", 1, 2),
                new ExpeditionStage(1, "Capitals & Borders", "Where the lines are drawn.", "geography", 1, 3),
                new ExpeditionStage(2, "Rivers, Ranges & Deserts", "The planet's physical geography.", "geography", 2, 3),
                new ExpeditionStage(3, "Nations & Peoples", "Who lives where, and why.", "geography", 2, 4),
                new ExpeditionStage(4, "Cities of the World", "The places everyone's heard of.", "geography", 3, 4),
                new ExpeditionStage(5, "The Far Corners", "The places most people haven't.", "geography", 3, 5),
                new ExpeditionStage(6, "World-Class", "Geography's hardest questions.", "geography", 4, 5),
            }),
        new Expedition("scientific-record", "The Scientific Record",
            "From first principles to the frontier — the story of how we know what we know.",
            "science", "atom", new[]
            {
                new ExpeditionStage(0, "First Principles", "The fundamentals everyone starts with.", "science", 1, 2),
                new ExpeditionStage(1, "Matter & Energy", "Physics and chemistry, from the ground up.", "science", 1, 3),
                new ExpeditionStage(2, "Life Itself", "Biology's big ideas.", "science", 2, 3),
                new ExpeditionStage(3, "The Great Discoveries", "The breakthroughs that changed everything.", "science", 2, 4),
                new ExpeditionStage(4, "The Scientists Behind It", "The people who did the work.", "science", 3, 4),
                new ExpeditionStage(5, "The Frontier", "Where the science is still being written.", "science", 3, 5),
                new ExpeditionStage(6, "The Comprehensive Exam", "Science's deepest cuts.", "science", 4, 5),
            }),
    };

    public static Expedition? Named(string id) => All.FirstOrDefault(e => e.Id == id);

    /// Every catalog expedition, paired with its progress row if one exists.
    public static List<(Expedition Expedition, ExpeditionProgress? Progress)> Available(RecordsStore records) =>
        All.Select(e => (e, Progress(records, e.Id))).ToList();

    public static ExpeditionProgress? Progress(RecordsStore records, string expeditionId) =>
        records.ExpeditionProgress.GetValueOrDefault(expeditionId);

    /// The question set for one stage — a fresh, difficulty-banded pull from the
    /// bundled corpus each attempt (a stage is replayable on a miss, so there's no
    /// "seen" exclusion the way a normal round has). Never-empty: relaxes to the
    /// whole category pool if the difficulty band comes up thin.
    public static List<Question> StartStage(CorpusDatabase corpus, Expedition expedition, int stageIndex)
    {
        var stage = expedition.Stages.FirstOrDefault(s => s.Index == stageIndex);
        if (stage is null) return new List<Question>();
        var pool = corpus.Questions(corpus.OrderedIds(stage.CategoryId));
        var banded = pool.Where(q => q.Difficulty >= stage.DifficultyLow && q.Difficulty <= stage.DifficultyHigh).ToList();
        if (banded.Count < stage.QuestionCount) banded = pool;
        return QueryHelpers.Shuffle(banded).Take(stage.QuestionCount).ToList();
    }

    /// A stage just finished — pass advances (and unlocks the next stage); the LAST
    /// stage passing writes the permanent certificate and clears the in-progress row
    /// (mirrors Marathon's finish). Fail leaves progress exactly where it was — the
    /// player stays on the same stage, "try again." `DebugHooks.ExpeditionForcePass`
    /// (docs/CLUB-FEATURES-BUILD.md gating convention) always records a pass — real
    /// autopilot can't reliably clear a real pass bar either.
    public static (bool Passed, ExpeditionCertificate? Certificate) RecordStageResult(
        RecordsStore records, Expedition expedition, int stageIndex, int correct, int total)
    {
        var stage = expedition.Stages.FirstOrDefault(s => s.Index == stageIndex);
        if (stage is null) return (false, null);

        var progress = records.ExpeditionProgress.GetValueOrDefault(expedition.Id)
            ?? new ExpeditionProgress { ExpeditionId = expedition.Id };
        var passed = correct >= stage.PassBar || DebugHooks.ExpeditionForcePass;

        progress.StageResults = progress.StageResults.Where(r => r.StageIndex != stageIndex).ToList();
        progress.StageResults.Add(new ExpeditionStageResult { StageIndex = stageIndex, Passed = passed, Correct = correct, Total = total });
        progress.LastPlayedAt = DateTime.UtcNow;
        if (passed) progress.CurrentStageIndex = Math.Max(progress.CurrentStageIndex, stageIndex + 1);

        if (!passed)
        {
            records.SaveExpeditionProgress(progress);
            return (false, null);
        }
        if (stageIndex < expedition.Stages.Count - 1)
        {
            records.SaveExpeditionProgress(progress);
            return (true, null);
        }

        // Final stage passed — write the certificate, retire the progress row.
        var totalScore = progress.StageResults.Sum(r => r.Correct);
        var cert = new ExpeditionCertificate
        {
            ExpeditionId = expedition.Id, Domain = expedition.Domain, Title = expedition.Title,
            TotalScore = totalScore, StagesCompleted = expedition.Stages.Count,
        };
        records.AppendExpeditionCertificate(cert);
        records.DeleteExpeditionProgress(expedition.Id);
        return (true, cert);
    }

    /// Every completed Expedition, most recent first — the permanent history (the
    /// Completed/certificates shelf).
    public static IReadOnlyList<ExpeditionCertificate> Certificates(RecordsStore records) => records.ExpeditionCertificates;

    /// A real, concrete illustration (MONETIZATION §4a: "a real preview, never a
    /// nag"). Mirrors the Apple/web/Android copy verbatim — the empty/first-run line
    /// from the design spec doubles as the non-member pitch since the hub/map are a
    /// real preview reachable by everyone.
    public static string PreviewLine() =>
        "Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace.";
}
