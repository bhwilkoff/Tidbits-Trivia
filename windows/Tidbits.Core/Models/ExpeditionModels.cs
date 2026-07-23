namespace Tidbits.Core.Models;

/// One themed stage inside an Expedition — a normal category/difficulty-band round
/// the EXISTING engine already plays (`GameMode.Classic`, via
/// `Expeditions.StartStage`). NOT a new game mode. The taxonomy (`TriviaCategory.All`)
/// is FLAT — no sub-domain like "1920s" or "South America" — so stages within one
/// Expedition differentiate by DIFFICULTY BAND, not sub-category (same constraint the
/// Knowledge Atlas hit; see docs/CLUB-FEATURES-BUILD.md "Feature 5"). Windows mirror
/// of Apple's `ExpeditionStage` (Core/Models/ExpeditionModels.swift) / Android's
/// `ExpeditionStage` (data/Expeditions.kt).
public sealed record ExpeditionStage(
    int Index, string Title, string Blurb, string CategoryId,
    int DifficultyLow, int DifficultyHigh, int QuestionCount = 10, int PassBar = 6);

/// A curated multi-stage campaign through one domain — the portable shape other
/// platforms mirror. Adding an expedition is additive: append to `Expeditions.All`;
/// no client change needed.
public sealed record Expedition(
    string Id, string Title, string Subtitle,
    /// `TriviaCategory.Id` this expedition is themed around (icon/color only — stages
    /// carry their own `CategoryId`, usually the same domain).
    string Domain, string Symbol, IReadOnlyList<ExpeditionStage> Stages)
{
    public int StageCount => Stages.Count;
}

/// One stage's outcome inside an in-progress Expedition — the progress JSON unit
/// (mirrors Apple's `ExpeditionStageResult` / Android's `ExpeditionStageResult`).
public sealed class ExpeditionStageResult
{
    public int StageIndex { get; set; }
    public bool Passed { get; set; }
    public int Correct { get; set; }
    public int Total { get; set; }
}

/// One in-progress Expedition. Unlike Marathon's at-most-one run, a player can
/// pursue SEVERAL campaigns at once — keyed by `ExpeditionId` in a dictionary on
/// `RecordsStore`, not a singleton. Persisted after every stage attempt so a player
/// can leave and come back over days or weeks.
public sealed class ExpeditionProgress
{
    public string ExpeditionId { get; set; } = "";
    public int CurrentStageIndex { get; set; }
    public List<ExpeditionStageResult> StageResults { get; set; } = new();
    public DateTime StartedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastPlayedAt { get; set; } = DateTime.UtcNow;
}

/// A completed Expedition — permanent (docs/CLUB-FEATURES-BUILD.md "Feature 5").
/// Written once the LAST stage passes; the in-progress `ExpeditionProgress` row is
/// deleted at the same time (mirrors Marathon's finish -> history + clear-the-run).
public sealed class ExpeditionCertificate
{
    public string ExpeditionId { get; set; } = "";
    public string Domain { get; set; } = "";
    public string Title { get; set; } = "";
    public DateTime CompletedAt { get; set; } = DateTime.UtcNow;
    public int TotalScore { get; set; }
    public int StagesCompleted { get; set; }
}
