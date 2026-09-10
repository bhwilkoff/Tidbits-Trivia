using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.App.Services;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A2.11 / 3.73 — a double-points round: question override > round > the night's setting,
/// and the round value rides the event file like the round timer.
public class RoundPointsTest
{
    private static Question Q(string id) => new()
    {
        Id = id, Prompt = "?", Options = new[] { "a", "b", "c", "d" }, CorrectIndex = 0,
        CategoryId = "film", Difficulty = 3, Explanation = "", SourceTitle = "", TemplateId = "hand",
    };

    [Fact]
    public void Question_override_beats_round_beats_night()
    {
        var data = GameData.FromDirectory(System.IO.Path.Combine(System.AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "Quick Night")
        {
            PointsPerCorrect = 1,
            RoundPoints = new List<int> { 2, 0 },
        };
        Assert.Equal(2, host.RoundPointsPerCorrect);   // round 0 before any question
        Assert.Equal(2, host.CurrentPoints);
        host.RoundPoints = new List<int>();
        Assert.Null(host.RoundPointsPerCorrect);
        Assert.Equal(1, host.CurrentPoints);
    }

    [Fact]
    public void Round_points_round_trip_through_the_event_file_and_absent_means_the_night()
    {
        var ev = new LiveEvent
        {
            Name = "N",
            Rounds = new[] { new NightRound { Kind = GameMode.Classic, Count = 1 }, new NightRound { Kind = GameMode.Classic, Count = 1 } },
            RoundQuestions = new List<IReadOnlyList<Question>> { new[] { Q("q1") }, new[] { Q("q2") } },
            RoundPoints = new List<int> { 3, 0 },
        };
        var json = LiveEventFile.Encode(ev);
        var rounds = System.Text.Json.JsonDocument.Parse(json).RootElement.GetProperty("event").GetProperty("rounds");
        Assert.Equal(3, rounds[0].GetProperty("points").GetInt32());
        Assert.False(rounds[1].TryGetProperty("points", out var p1) && p1.ValueKind == System.Text.Json.JsonValueKind.Number);
        var back = LiveEventFile.Decode(json);
        Assert.Equal(new List<int> { 3, 0 }, back.RoundPoints);
    }
}
