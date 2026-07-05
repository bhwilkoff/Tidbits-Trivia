using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Models;

/// The game modes (port of Core/Models/GameMode.swift). The string IDs are the
/// wire values — keep them byte-identical to the Swift rawValues. Serializes as
/// that string (not the enum ordinal) for cross-platform wire compatibility.
[JsonConverter(typeof(GameModeJsonConverter))]
public enum GameMode
{
    Classic, TimeAttack, Survival, Stake, Sweep, PictureId, ThisOrThat, ClosestCall,
    Ordering, Matching, TypeAnswer, OddOneOut, Ladder, Enumerate, BarTrivia, Mix, Daily,
}

/// (De)serializes GameMode as its wire string ("classic", "timeAttack", …).
public sealed class GameModeJsonConverter : JsonConverter<GameMode>
{
    public override GameMode Read(ref Utf8JsonReader reader, Type _, JsonSerializerOptions __) =>
        GameModeExtensions.FromId(reader.GetString() ?? "") ?? GameMode.Classic;

    public override void Write(Utf8JsonWriter writer, GameMode value, JsonSerializerOptions _) =>
        writer.WriteStringValue(value.Id());
}

public readonly record struct StakeChip(int Value, string Label, int Count);

public static class GameModeExtensions
{
    /// The wire ID (Swift rawValue) — used in RTDB/JSON/persistence.
    public static string Id(this GameMode m) => m switch
    {
        GameMode.Classic => "classic",
        GameMode.TimeAttack => "timeAttack",
        GameMode.Survival => "survival",
        GameMode.Stake => "stake",
        GameMode.Sweep => "sweep",
        GameMode.PictureId => "pictureId",
        GameMode.ThisOrThat => "thisOrThat",
        GameMode.ClosestCall => "closestCall",
        GameMode.Ordering => "ordering",
        GameMode.Matching => "matching",
        GameMode.TypeAnswer => "typeAnswer",
        GameMode.OddOneOut => "oddOneOut",
        GameMode.Ladder => "ladder",
        GameMode.Enumerate => "enumerate",
        GameMode.BarTrivia => "barTrivia",
        GameMode.Mix => "mix",
        GameMode.Daily => "daily",
        _ => "classic",
    };

    public static GameMode? FromId(string id) =>
        System.Enum.GetValues<GameMode>().Cast<GameMode?>().FirstOrDefault(m => m!.Value.Id() == id);

    public static string Title(this GameMode m) => m switch
    {
        GameMode.Classic => "Classic",
        GameMode.TimeAttack => "Time Attack",
        GameMode.Survival => "Survival",
        GameMode.Stake => "Stake",
        GameMode.Sweep => "Sweep",
        GameMode.PictureId => "Picture ID",
        GameMode.ThisOrThat => "Which First?",
        GameMode.ClosestCall => "Closest Call",
        GameMode.Ordering => "In Order",
        GameMode.Matching => "Match Up",
        GameMode.TypeAnswer => "Name It",
        GameMode.OddOneOut => "Odd One Out",
        GameMode.Ladder => "Ladder",
        GameMode.Enumerate => "Name as Many",
        GameMode.BarTrivia => "Trivia Night",
        GameMode.Mix => "Custom Mix",
        GameMode.Daily => "Daily Tidbit",
        _ => "Classic",
    };

    public static string Blurb(this GameMode m) => m switch
    {
        GameMode.Classic => "Ten questions. Speed counts.",
        GameMode.TimeAttack => "How many in 60 seconds?",
        GameMode.Survival => "One wrong answer ends it.",
        GameMode.Stake => "Bet your confidence. No risk.",
        GameMode.Sweep => "Fill the set. Beat your best.",
        GameMode.PictureId => "Name what you see.",
        GameMode.ThisOrThat => "Which came first?",
        GameMode.ClosestCall => "How close can you get?",
        GameMode.Ordering => "Arrange them in time.",
        GameMode.Matching => "Link each pair.",
        GameMode.TypeAnswer => "Type the answer.",
        GameMode.OddOneOut => "Which doesn't belong?",
        GameMode.Ladder => "Climb from easy to hard.",
        GameMode.Enumerate => "How many can you name?",
        GameMode.BarTrivia => "Host a night. Every kind of round.",
        GameMode.Mix => "Your picked modes, shuffled together.",
        GameMode.Daily => "Everyone's puzzle. Keep your streak.",
        _ => "",
    };

    /// The round title when used as a Trivia Night round type.
    public static string NightRoundTitle(this GameMode m) => m switch
    {
        GameMode.Classic => "General Knowledge",
        GameMode.PictureId => "Picture Round",
        GameMode.ThisOrThat => "Which Came First?",
        GameMode.ClosestCall => "Closest Wins",
        GameMode.Ordering => "Put Them In Order",
        GameMode.Matching => "Match-Up",
        GameMode.TypeAnswer => "Name It",
        GameMode.OddOneOut => "Odd One Out",
        GameMode.Enumerate => "Name As Many",
        _ => m.Title(),
    };

    /// Per-question time budget in seconds (null = the mode's own clock).
    public static double? PerQuestionSeconds(this GameMode m) => m switch
    {
        GameMode.Classic => 20,
        GameMode.TimeAttack => null, // global 60s clock
        GameMode.Survival => 15,
        GameMode.Stake => 30,
        GameMode.Sweep => 12,
        GameMode.PictureId => 20,
        GameMode.ThisOrThat => 12,
        GameMode.ClosestCall => 25,
        GameMode.Ordering => 35,
        GameMode.Matching => 40,
        GameMode.TypeAnswer => 25,
        GameMode.OddOneOut => 20,
        GameMode.Ladder => 20,
        GameMode.Enumerate => 60,
        GameMode.BarTrivia => 20,
        GameMode.Mix => 20,
        GameMode.Daily => 30,
        _ => 20,
    };

    public static int QuestionCount(this GameMode m) => m switch
    {
        GameMode.Classic => 10,
        GameMode.TimeAttack => 99,
        GameMode.Survival => 99,
        GameMode.Stake => 8,
        GameMode.Sweep => 12,
        GameMode.PictureId => 10,
        GameMode.ThisOrThat => 10,
        GameMode.ClosestCall => 8,
        GameMode.Ordering => 6,
        GameMode.Matching => 6,
        GameMode.TypeAnswer => 8,
        GameMode.OddOneOut => 8,
        GameMode.Ladder => 10,
        GameMode.Enumerate => 3,
        GameMode.BarTrivia => 20,
        GameMode.Mix => 10,
        GameMode.Daily => 7,
        _ => 10,
    };

    public static double? GlobalClockSeconds(this GameMode m) => m == GameMode.TimeAttack ? 60 : null;

    /// Whether spaced-review misses (plain corpus MCQ) may be woven into a round.
    public static bool AcceptsReview(this GameMode m) => m switch
    {
        GameMode.Classic or GameMode.TimeAttack or GameMode.Survival
            or GameMode.Stake or GameMode.Sweep or GameMode.Ladder => true,
        _ => false,
    };

    /// Stake mode: the fixed budget of confidence chips for one round
    /// (sum of Count == QuestionCount). Adds-only — a wrong answer earns 0.
    public static readonly IReadOnlyList<StakeChip> StakeBudget = new[]
    {
        new StakeChip(3, "Sure", 2),
        new StakeChip(2, "Likely", 3),
        new StakeChip(1, "Hunch", 3),
    };
}
