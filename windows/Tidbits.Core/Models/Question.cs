using System.Text.Json.Serialization;

namespace Tidbits.Core.Models;

/// A single trivia question — identical shape whether pre-baked in the corpus or
/// generated live from a Wikipedia article (port of Core/Models/Question.swift).
/// JSON keys match the Swift Codable output so the same corpus/wire data loads.
public sealed record Question
{
    [JsonPropertyName("id")] public required string Id { get; init; }
    [JsonPropertyName("prompt")] public required string Prompt { get; init; }
    [JsonPropertyName("options")] public required IReadOnlyList<string> Options { get; init; } // exactly 4; index 0..3
    [JsonPropertyName("correctIndex")] public int CorrectIndex { get; init; }
    [JsonPropertyName("categoryID")] public required string CategoryId { get; init; }
    [JsonPropertyName("difficulty")] public int Difficulty { get; init; } // 1 (easy) … 5 (hard)
    [JsonPropertyName("explanation")] public string Explanation { get; init; } = "";
    [JsonPropertyName("sourceTitle")] public string SourceTitle { get; init; } = "";
    [JsonPropertyName("sourceURL")] public string? SourceUrl { get; init; }
    [JsonPropertyName("templateID")] public string TemplateId { get; init; } = "";
    [JsonPropertyName("tags")] public IReadOnlyList<string> Tags { get; init; } = []; // Wikipedia-category topic keywords
    [JsonPropertyName("imageURL")] public string? ImageUrl { get; init; }        // Picture ID
    [JsonPropertyName("closest")] public ClosestSpec? Closest { get; init; }     // Closest Call
    [JsonPropertyName("ordering")] public IReadOnlyList<string>? Ordering { get; init; } // items in CORRECT order
    [JsonPropertyName("matching")] public MatchSpec? Matching { get; init; }     // Matching
    [JsonPropertyName("accepted")] public IReadOnlyList<string>? Accepted { get; init; } // Type-the-answer
    [JsonPropertyName("enumerate")] public EnumSpec? Enumerate { get; init; }    // Enumeration
    [JsonPropertyName("roundIndex")] public int? RoundIndex { get; init; }       // Trivia Night round (runtime)

    [JsonIgnore]
    public string CorrectAnswer =>
        CorrectIndex >= 0 && CorrectIndex < Options.Count
            ? Options[CorrectIndex]
            : Closest?.FormattedAnswer ?? "";
}

/// Closest Call numeric question: estimate a value on a linear slider over
/// [min, max]; scored by proximity to `answer` within `tolerance` (adds-only).
public sealed record ClosestSpec
{
    [JsonPropertyName("answer")] public double Answer { get; init; }
    [JsonPropertyName("min")] public double Min { get; init; }
    [JsonPropertyName("max")] public double Max { get; init; }
    [JsonPropertyName("step")] public double Step { get; init; }
    [JsonPropertyName("tolerance")] public double Tolerance { get; init; }
    [JsonPropertyName("unit")] public string Unit { get; init; } = "";

    public const int MaxPoints = 50;

    /// Points (0…MaxPoints) — full at exact, 0 at/over tolerance.
    public int Points(double guess)
    {
        var error = Math.Abs(guess - Answer);
        if (error >= Tolerance) return 0;
        return (int)Math.Round(MaxPoints * (1 - error / Tolerance));
    }

    /// "Close enough" to count as correct for streaks / the emoji grid.
    public bool IsClose(double guess) => Math.Abs(guess - Answer) <= Tolerance / 2;

    [JsonIgnore]
    public string FormattedAnswer
    {
        get
        {
            var n = Answer == Math.Round(Answer)
                ? ((long)Answer).ToString()
                : Answer.ToString(System.Globalization.CultureInfo.InvariantCulture);
            return string.IsNullOrEmpty(Unit) ? n : $"{n} {Unit}";
        }
    }
}

/// Matching: values[i] is the correct match for keys[i]; the client shuffles for display.
public sealed record MatchSpec
{
    [JsonPropertyName("keys")] public required IReadOnlyList<string> Keys { get; init; }
    [JsonPropertyName("values")] public required IReadOnlyList<string> Values { get; init; }
}

/// Enumeration: each group is one accepted answer ([canonical, alias, …]); a group
/// fills only once; the display name is group[0].
public sealed record EnumSpec
{
    [JsonPropertyName("groups")] public required IReadOnlyList<IReadOnlyList<string>> Groups { get; init; }
    [JsonIgnore] public int Total => Groups.Count;
    [JsonIgnore] public IReadOnlyList<string> DisplayNames => Groups.Select(g => g.Count > 0 ? g[0] : "").ToList();
}

/// Whether the player got it right, and how fast — drives speed scoring, streaks,
/// and spaced re-ask of missed questions.
public sealed record AnsweredQuestion
{
    public required Question Question { get; init; }
    public int? ChosenIndex { get; init; } // null = timed out
    public double SecondsTaken { get; init; }
    public bool IsCorrect => ChosenIndex == Question.CorrectIndex;
}
