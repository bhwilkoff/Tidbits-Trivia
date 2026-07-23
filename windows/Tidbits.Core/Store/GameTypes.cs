using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// One confidence tier in Stake mode's budget.
public sealed class StakeTier
{
    public int Value { get; init; }
    public string Label { get; init; } = "";
    public int Remaining { get; set; }
}

/// One confidence tier's outcome in a Stake round (F1 calibration).
public struct StakeOutcome
{
    [JsonPropertyName("hits")] public int Hits { get; set; }
    [JsonPropertyName("total")] public int Total { get; set; }
}

/// Immutable end-of-game payload — drives results/recap + the record writes.
public sealed record GameSummary
{
    public required GameMode Mode { get; init; }
    public required TriviaCategory Category { get; init; }
    public int Score { get; init; }
    public int Correct { get; init; }
    public int Total { get; init; }
    public int MaxStreak { get; init; }
    public required IReadOnlyList<AnsweredQuestion> Answered { get; init; }
    public IReadOnlyDictionary<int, StakeOutcome> StakeOutcomes { get; init; } = new Dictionary<int, StakeOutcome>();
    public string? DailyDay { get; init; }

    public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
    public IReadOnlyList<AnsweredQuestion> Missed => Answered.Where(a => !a.IsCorrect).ToList();
}

/// Test/screenshot hooks (env-gated in the app; false in normal play). Mirrors the
/// Apple DebugHooks — autopilot drives a night straight through without round holds.
public static class DebugHooks
{
    public static bool Autopilot { get; set; }

    /// Pre-launch Club override (docs/CLUB-FEATURES-BUILD.md gating convention) — there
    /// are no real purchases yet, so `TIDBITS_CLUB=1` forces every Club gate open. No-op
    /// (false) whenever the env var is unset, exactly like the Apple `ProcessInfo`
    /// equivalent (`DebugHooks.forceClub`).
    public static bool ForceClub => Environment.GetEnvironmentVariable("TIDBITS_CLUB") == "1";

    /// Club Expedition stage force-pass (docs/CLUB-FEATURES-BUILD.md "Feature 5") — a
    /// played stage always records as a pass regardless of score, mirroring Apple's
    /// TIDBITS_EXPEDITION_FORCE_PASS / Android's `Expeditions.debugForcePass`.
    /// Settable directly (like `Autopilot`) rather than env-only, so a test can flip
    /// it without touching the process environment. False in normal play.
    public static bool ExpeditionForcePass { get; set; }
}
