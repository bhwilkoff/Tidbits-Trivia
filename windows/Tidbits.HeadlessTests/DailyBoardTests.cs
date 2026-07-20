using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The Daily board is a cross-platform data plane — percentile + marks MUST match
/// js/api.js and the Swift DailyBoard, or a Windows player's rank/per-question row
/// disagrees with a phone player's. Pinned here.
public class DailyBoardTests
{
    [Fact]
    public void Percentile_matches_the_cross_platform_reference()
    {
        // Same histogram the web render was verified against (n=2310).
        var hist = new Dictionary<string, int>
        {
            ["0"] = 50, ["100"] = 150, ["200"] = 400, ["300"] = 600,
            ["420"] = 700, ["540"] = 300, ["600"] = 110,
        };
        Assert.Equal(82, DailyBoardApi.Percentile(hist, 430));   // 1900 below / 2310
        Assert.Equal(0, DailyBoardApi.Percentile(hist, 0));      // nobody below
        Assert.Equal(100, DailyBoardApi.Percentile(hist, 1000)); // everybody below
    }

    [Fact]
    public void Empty_histogram_yields_null()
    {
        Assert.Null(DailyBoardApi.Percentile(new Dictionary<string, int>(), 300));
    }

    [Fact]
    public void Marks_align_to_pickDaily_order_not_play_order()
    {
        var qids = new[] { "q1", "q2", "q3", "q4", "q5", "q6", "q7" };
        // Answered in a DIFFERENT order than qids; marks must still be qid-aligned.
        var answered = new List<AnsweredQuestion>
        {
            Ans("q3", true), Ans("q1", true), Ans("q7", false), Ans("q2", true),
            Ans("q5", false), Ans("q4", true), Ans("q6", true),
        };
        // qid order q1..q7: q1✓ q2✓ q3✓ q4✓ q5✗ q6✓ q7✗
        Assert.Equal("1111010", DailyBoardApi.Marks(answered, qids));
    }

    [Fact]
    public void Marks_are_zero_for_a_question_not_answered()
    {
        var qids = new[] { "a", "b", "c" };
        var answered = new List<AnsweredQuestion> { Ans("a", true) };  // b, c missing
        Assert.Equal("100", DailyBoardApi.Marks(answered, qids));
    }

    private static AnsweredQuestion Ans(string id, bool correct)
    {
        var q = new Question
        {
            Id = id, Prompt = "?", Options = new[] { "x", "y" }, CorrectIndex = 0,
            CategoryId = "mixed", Difficulty = 3, Explanation = "", SourceTitle = "", SourceUrl = "",
        };
        return new AnsweredQuestion { Question = q, ChosenIndex = correct ? 0 : 1, SecondsTaken = 1 };
    }
}
