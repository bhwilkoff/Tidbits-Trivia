using System.Text.Json.Serialization;

namespace Tidbits.Core.Models;

/// How a configured night is played (Decision 033). Port of NightPlan.swift.
public enum NightStartMode { Solo, Host }

/// One round: a fixed count of one question TYPE. Codable — a host serializes the
/// plan to every joiner so each device builds the SAME night.
public sealed record NightRound
{
    [JsonPropertyName("kind")] public GameMode Kind { get; init; }
    [JsonPropertyName("count")] public int Count { get; init; }

    [JsonIgnore] public string Title => Kind.NightRoundTitle();
}

/// A Trivia Night — a sequence of themed rounds. Wire type (sent to joiners).
/// `teams` is lenient: an Android host omits it when empty, so a missing key
/// decodes to [] (System.Text.Json leaves the default).
public sealed record NightPlan
{
    [JsonPropertyName("rounds")] public required IReadOnlyList<NightRound> Rounds { get; init; }
    [JsonPropertyName("teams")] public IReadOnlyList<string> Teams { get; init; } = [];

    [JsonIgnore] public int TotalQuestions => Rounds.Sum(r => r.Count);
    [JsonIgnore] public bool IsTeam => Teams.Count >= 2;

    /// The question types a night can be built from, in a sensible running order.
    public static readonly IReadOnlyList<GameMode> AllKinds = new[]
    {
        GameMode.Classic, GameMode.PictureId, GameMode.ThisOrThat, GameMode.ClosestCall,
        GameMode.Ordering, GameMode.Matching, GameMode.TypeAnswer, GameMode.OddOneOut, GameMode.Enumerate,
    };

    public static readonly NightPlan Quick = new()
    {
        Rounds = new[]
        {
            new NightRound { Kind = GameMode.Classic, Count = 5 },
            new NightRound { Kind = GameMode.PictureId, Count = 4 },
            new NightRound { Kind = GameMode.ClosestCall, Count = 3 },
        },
    };

    public static readonly NightPlan Pub = new()
    {
        Rounds = new[]
        {
            new NightRound { Kind = GameMode.Classic, Count = 6 },
            new NightRound { Kind = GameMode.PictureId, Count = 4 },
            new NightRound { Kind = GameMode.ThisOrThat, Count = 4 },
            new NightRound { Kind = GameMode.ClosestCall, Count = 4 },
            new NightRound { Kind = GameMode.OddOneOut, Count = 4 },
        },
    };

    public static readonly NightPlan Works = new()
    {
        Rounds = AllKinds.Select(k => new NightRound { Kind = k, Count = k == GameMode.Enumerate ? 2 : 4 }).ToList(),
    };

    public static readonly IReadOnlyList<(string Name, string Blurb, NightPlan Plan)> Presets = new[]
    {
        ("Quick Night", "3 rounds · ~12 questions", Quick),
        ("Pub Night", "5 rounds · ~22 questions", Pub),
        ("The Works", "Every question type · ~28", Works),
    };
}
