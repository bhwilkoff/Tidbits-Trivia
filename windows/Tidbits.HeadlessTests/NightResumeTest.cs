using System;
using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A2.13 / 3.80 — the night the host's app died in the middle of.
public class NightResumeTest
{
    private static string TempPath() =>
        System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tidbits-resume-" + Guid.NewGuid().ToString("N") + ".json");

    private static ResumedNight Snap(int index = 3, int total = 12, DateTimeOffset? at = null) => new()
    {
        Code = "AB12", Title = "Tuesday Quiz", Index = index, Total = total, Revealed = true,
        PaperTeams = new[] { new ResumedNight.Team { Name = "The Bar", Score = 4 } },
        PointsPerCorrect = 2, WrongAnswerPenalty = 1,
        SavedAt = at ?? DateTimeOffset.Now,
    };

    [Fact]
    public void A_saved_night_survives_a_relaunch_with_everything_the_host_held()
    {
        var path = TempPath();
        new NightResume(path).Save(Snap());
        var again = new NightResume(path).Pending();
        Assert.NotNull(again);
        Assert.Equal("AB12", again!.Code);
        Assert.Equal(3, again.Index);
        Assert.True(again.Revealed);
        Assert.Equal("The Bar", Assert.Single(again.PaperTeams).Name);
        Assert.Equal(4, again.PaperTeams[0].Score);
        Assert.Equal(2, again.PointsPerCorrect);
        Assert.Equal(1, again.WrongAnswerPenalty);
        System.IO.File.Delete(path);
    }

    [Fact]
    public void The_card_says_where_the_host_was()
    {
        Assert.Equal("question 4 of 12", Snap().PositionLine);
        Assert.Equal("not started", (Snap() with { Total = 0 }).PositionLine);
        // Never "question 13 of 12" — the last question is where a finished night sits.
        Assert.Equal("question 12 of 12", (Snap(index: 40) with { Total = 12 }).PositionLine);
    }

    [Fact]
    public void Last_weeks_night_is_not_offered()
    {
        var path = TempPath();
        var store = new NightResume(path);
        store.Save(Snap(at: DateTimeOffset.Now - TimeSpan.FromHours(7)));
        Assert.Null(store.Pending());          // stale: the room left hours ago
        store.Save(Snap(at: DateTimeOffset.Now - TimeSpan.FromMinutes(20)));
        Assert.NotNull(store.Pending());
        System.IO.File.Delete(path);
    }

    [Fact]
    public void A_night_that_ended_properly_never_offers_to_resume()
    {
        var path = TempPath();
        var store = new NightResume(path);
        store.Save(Snap());
        store.Clear();
        Assert.Null(store.Pending());
        Assert.Null(new NightResume(path).Pending());   // and it stays gone across a relaunch
    }
}

/// A2.13: the host picks the night back up with what only the host held.
public class NightResumeRestoreTest
{
    [Fact]
    public void Restoring_puts_back_the_paper_teams_the_hidden_names_and_the_position()
    {
        var data = Tidbits.App.Services.GameData.FromDirectory(System.IO.Path.Combine(System.AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(Tidbits.Core.Models.NightPlan.Quick, Tidbits.Core.Models.TriviaCategory.Named("mixed"), data.Provider, "Quick Night");
        host.RestoreFrom(new ResumedNight
        {
            Code = "AB12", Title = "Quick Night", Index = 2, Total = 5, Revealed = true,
            PaperTeams = new[] { new ResumedNight.Team { Name = "The Bar", Score = 4 }, new ResumedNight.Team { Name = "Corner", Score = 1 } },
            Hidden = new[] { "rude-uid" },
            Questions = Enumerable.Range(0, 5).Select(i => new Tidbits.Core.Models.Question
            {
                Id = "q" + i, Prompt = "Q" + i + "?", Options = new[] { "A", "B", "C", "D" }, CorrectIndex = 0,
                CategoryId = "mixed", Difficulty = 3, Explanation = "", RoundIndex = 0,
            }).ToList(),
            PointsPerCorrect = 3, WrongAnswerPenalty = 1, SavedAt = DateTimeOffset.Now,
        });
        Assert.True(host.Revealed);
        // The night plays the questions it was playing — never a fresh corpus draw.
        Assert.Equal(5, host.Questions.Count);
        Assert.Equal("q2", host.Current?.Id);
        Assert.Equal(3, host.PointsPerCorrect);
        Assert.Equal(1, host.WrongAnswerPenalty);
        Assert.True(host.IsHidden("rude-uid"));
        var paper = host.Standings.Where(s => s.Id.StartsWith("paper:", StringComparison.Ordinal)).ToDictionary(s => s.Name, s => s.Score);
        Assert.Equal(4, paper["The Bar"]);
        Assert.Equal(1, paper["Corner"]);
        Assert.Equal(2, host.Index);
    }

    [Fact]
    public void A_snapshot_with_no_questions_clamps_to_the_front_rather_than_past_the_end()
    {
        var data = Tidbits.App.Services.GameData.FromDirectory(System.IO.Path.Combine(System.AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(Tidbits.Core.Models.NightPlan.Quick, Tidbits.Core.Models.TriviaCategory.Named("mixed"), data.Provider, "Quick Night");
        host.RestoreFrom(new ResumedNight { Code = "AB12", Index = 40, SavedAt = DateTimeOffset.Now });
        Assert.Equal(0, host.Index);
    }

    [Fact]
    public void The_questions_round_trip_through_the_file()
    {
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tidbits-resume-" + Guid.NewGuid().ToString("N") + ".json");
        new NightResume(path).Save(new ResumedNight
        {
            Code = "AB12", Index = 1, SavedAt = DateTimeOffset.Now,
            Questions = new[] { new Tidbits.Core.Models.Question { Id = "q9", Prompt = "P?", Options = new[] { "A", "B" }, CorrectIndex = 1, CategoryId = "mixed", Difficulty = 2, Explanation = "", RoundIndex = 3 } },
            Plan = Tidbits.Core.Models.NightPlan.Quick,
        });
        var again = new NightResume(path).Pending();
        Assert.Equal("q9", Assert.Single(again!.Questions).Id);
        Assert.Equal(3, again.Questions[0].RoundIndex);
        Assert.Equal(3, again.Plan!.Rounds.Count);
        System.IO.File.Delete(path);
    }
}
