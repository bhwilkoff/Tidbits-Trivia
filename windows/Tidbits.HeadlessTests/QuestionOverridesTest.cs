using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// 3.58 + 3.59 — the numeric tie-break and the per-question overrides.
public class QuestionOverridesTest
{
    [Fact]
    public void Closest_guess_wins_and_an_exact_tie_is_stable()
    {
        var g = new Dictionary<string, double> { ["a"] = 1900, ["b"] = 1880, ["c"] = 1700 };
        Assert.Equal("b", LiveNightHost.ClosestWinner(1889, g));
        Assert.Equal("a", LiveNightHost.ClosestWinner(1890, new Dictionary<string, double> { ["b"] = 1880, ["a"] = 1900 }));
        Assert.Null(LiveNightHost.ClosestWinner(1, new Dictionary<string, double>()));
    }

    private static Question Q(string id) => new()
    {
        Id = id, Prompt = "p " + id, Options = new[] { "a", "b", "c", "d" }, CorrectIndex = 0,
        CategoryId = "mixed", Difficulty = 2, Explanation = "", SourceTitle = "", TemplateId = "hand",
    };

    [Fact]
    public void Overrides_round_trip_through_the_event_file_and_absent_means_default()
    {
        var ev = new LiveEvent
        {
            Name = "N",
            Rounds = new[] { new NightRound { Kind = GameMode.Classic, Count = 2 }, new NightRound { Kind = GameMode.Classic, Count = 1 } },
            RoundQuestions = new List<IReadOnlyList<Question>> { new[] { Q("q1"), Q("q2") }, new[] { Q("q3") } },
            RoundQuestionTimers = new List<IReadOnlyList<int>> { new[] { 0, 45 } },
            RoundQuestionPoints = new List<IReadOnlyList<int>> { new[] { 3, 0 }, new[] { 0 } },
            RoundQuestionNotes = new List<IReadOnlyList<string>> { new[] { "Say KEE-ah-noo", "" } },
        };
        Assert.Equal("Say KEE-ah-noo", ev.QuestionNote(0, 0)); Assert.Null(ev.QuestionNote(0, 1)); Assert.Null(ev.QuestionNote(1, 0));
        Assert.Null(ev.QuestionTimer(0, 0)); Assert.Equal(45, ev.QuestionTimer(0, 1)); Assert.Null(ev.QuestionTimer(1, 0));
        Assert.Equal(3, ev.QuestionPoints(0, 0)); Assert.Null(ev.QuestionPoints(0, 1)); Assert.Null(ev.QuestionPoints(5, 5));

        var json = LiveEventFile.Encode(ev);
        var rounds = System.Text.Json.JsonDocument.Parse(json).RootElement.GetProperty("event").GetProperty("rounds");
        static int?[] Ints(System.Text.Json.JsonElement a) =>
            a.EnumerateArray().Select(e => e.ValueKind == System.Text.Json.JsonValueKind.Null ? (int?)null : e.GetInt32()).ToArray();
        Assert.Equal(new int?[] { null, 45 }, Ints(rounds[0].GetProperty("questionTimers")));
        Assert.Equal(new int?[] { 3, null }, Ints(rounds[0].GetProperty("questionPoints")));
        // Round 2 has nothing set: the key is absent (or null), not a list of nulls.
        Assert.False(rounds[1].TryGetProperty("questionPoints", out var r2) && r2.ValueKind == System.Text.Json.JsonValueKind.Array);
        var back = LiveEventFile.Decode(json);
        Assert.Equal(45, back.QuestionTimer(0, 1)); Assert.Null(back.QuestionTimer(0, 0));
        Assert.Equal(3, back.QuestionPoints(0, 0)); Assert.Empty(back.RoundQuestionPoints[1]);
        Assert.Equal("Say KEE-ah-noo", back.QuestionNote(0, 0)); Assert.Null(back.QuestionNote(0, 1)); Assert.Empty(back.RoundQuestionNotes[1]);
    }
}
