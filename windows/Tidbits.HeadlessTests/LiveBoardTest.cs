using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G5 — the pick-your-category board. The SAME cases as Swift
/// TidbitsTriviaTests/LiveBoardTests.swift: a Windows host and a Mac host must
/// build the same board from the same pool and agree on who picks next.
public class LiveBoardTest
{
    private static Question Q(string id, string cat, int diff) => new()
    {
        Id = id, Prompt = "p", Options = new[] { "a", "b", "c", "d" },
        CorrectIndex = 0, CategoryId = cat, Difficulty = diff,
    };

    private static List<Question> FullPool(params string[] cats) =>
        cats.SelectMany(c => Enumerable.Range(1, 5).Select(t => Q($"{c}-{t}", c, t))).ToList();

    [Fact]
    public void A_full_pool_builds_every_cell()
    {
        var b = LiveBoardBuilder.Build(FullPool("history", "music"), new[] { "history", "music" });
        Assert.Equal(10, b.Cells.Count);
        Assert.Equal("history-3", b.Cell("history", 3)!.QuestionId);
    }

    [Fact]
    public void Points_come_from_the_tier_not_the_question()
    {
        var b = LiveBoardBuilder.Build(FullPool("history"), new[] { "history" });
        Assert.Equal(100, b.Cell("history", 1)!.Points);
        Assert.Equal(500, b.Cell("history", 5)!.Points);
    }

    [Fact]
    public void A_cell_the_pool_cannot_fill_is_absent_not_a_dead_button()
    {
        var pool = FullPool("history").Where(q => q.Difficulty != 4).ToList();
        var b = LiveBoardBuilder.Build(pool, new[] { "history" });
        Assert.Equal(4, b.Cells.Count);
        Assert.Null(b.Cell("history", 4));
    }

    [Fact]
    public void No_question_is_used_twice()
    {
        var b = LiveBoardBuilder.Build(new List<Question> { Q("shared", "history", 1) },
                                       new[] { "history", "history" });
        Assert.Single(b.Cells);
    }

    [Fact]
    public void Taking_a_cell_marks_it_and_taking_it_twice_is_refused()
    {
        var b = LiveBoardBuilder.Build(FullPool("history"), new[] { "history" });
        Assert.True(b.Take("history", 2));
        Assert.True(b.Cell("history", 2)!.Taken);
        Assert.False(b.Take("history", 2));
    }

    [Fact]
    public void Taking_a_cell_that_does_not_exist_is_refused()
    {
        var b = LiveBoardBuilder.Build(FullPool("history"), new[] { "history" });
        Assert.False(b.Take("music", 3));
        Assert.False(b.Take("history", 9));
    }

    [Fact]
    public void Remaining_and_completion_track_the_picks()
    {
        var b = LiveBoardBuilder.Build(FullPool("history"), new[] { "history" });
        Assert.Equal(5, b.Remaining.Count);
        Assert.Equal(1500, b.PointsRemaining);
        for (int t = 1; t <= 5; t++) b.Take("history", t);
        Assert.True(b.IsComplete);
        Assert.Equal(0, b.PointsRemaining);
    }

    [Fact]
    public void Only_fully_fillable_categories_are_offered()
    {
        var pool = FullPool("history", "music")
            .Where(q => !(q.CategoryId == "music" && q.Difficulty == 5)).ToList();
        Assert.Equal(new[] { "history" }, LiveBoardBuilder.FillableCategories(pool));
    }

    [Fact]
    public void The_team_that_answered_correctly_picks_next()
    {
        var teams = new[] { "Alpha", "Bravo", "Charlie" };
        Assert.Equal("Charlie", LiveBoardBuilder.NextChooser("Alpha", "Charlie", teams));
    }

    [Fact]
    public void When_nobody_is_right_the_pick_rotates()
    {
        var teams = new[] { "Alpha", "Bravo", "Charlie" };
        Assert.Equal("Bravo", LiveBoardBuilder.NextChooser("Alpha", null, teams));
        Assert.Equal("Alpha", LiveBoardBuilder.NextChooser("Charlie", null, teams));
    }

    [Fact]
    public void A_correct_answer_from_a_team_that_has_left_falls_back_to_rotation()
    {
        var teams = new[] { "Alpha", "Bravo" };
        Assert.Equal("Bravo", LiveBoardBuilder.NextChooser("Alpha", "Ghost", teams));
    }

    [Fact]
    public void An_empty_room_has_no_chooser() =>
        Assert.Null(LiveBoardBuilder.NextChooser(null, null, new string[0]));
}
