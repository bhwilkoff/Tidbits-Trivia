using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// The authoritative per-shape Live scoring — a joiner's Answer vs the host's local
/// Question. Covers MCQ, numeric proximity, ordering, matching, type-answer, enumerate.
public class LiveScoringTest
{
    private static Question Mcq() => new()
    {
        Id = "q", Prompt = "P", Options = new[] { "A", "B", "C", "D" }, CorrectIndex = 2, CategoryId = "mixed",
    };

    [Fact]
    public void Mcq_scores_the_correct_choice()
    {
        var q = Mcq();
        Assert.Equal(5, LiveScoring.Score(q, new LiveRoom.Answer { Choice = 2, Ts = 1 }, [], [], 5));
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Choice = 0, Ts = 1 }, [], [], 5));
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Ts = 1 }, [], [], 5)); // no answer
    }

    [Fact]
    public void Numeric_scores_by_proximity()
    {
        var q = new Question
        {
            Id = "q", Prompt = "P", Options = [], CategoryId = "mixed",
            Closest = new ClosestSpec { Answer = 100, Min = 0, Max = 200, Step = 1, Tolerance = 20, Unit = "" },
        };
        Assert.Equal(50, LiveScoring.Score(q, new LiveRoom.Answer { Number = 100, Ts = 1 }, [], [], 1)); // exact = max
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Number = 130, Ts = 1 }, [], [], 1));  // beyond tolerance
    }

    [Fact]
    public void Ordering_gives_partial_credit_per_position()
    {
        var q = new Question { Id = "q", Prompt = "P", Options = [], CategoryId = "mixed", Ordering = new[] { "A", "B", "C" } };
        var shuffled = new[] { "C", "A", "B" };
        // player arranges indices [1,2,0] → A,B,C → all 3 correct
        Assert.Equal(3, LiveScoring.Score(q, new LiveRoom.Answer { Order = new[] { 1, 2, 0 }, Ts = 1 }, shuffled, [], 1));
        // [0,1,2] → C,A,B → 0 correct positions
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Order = new[] { 0, 1, 2 }, Ts = 1 }, shuffled, [], 1));
    }

    [Fact]
    public void Matching_gives_partial_credit_per_pair()
    {
        var q = new Question
        {
            Id = "q", Prompt = "P", Options = [], CategoryId = "mixed",
            Matching = new MatchSpec { Keys = new[] { "k1", "k2" }, Values = new[] { "v1", "v2" } },
        };
        var shuffledValues = new[] { "v2", "v1" };
        // key0→v1 (shuffled idx 1), key1→v2 (shuffled idx 0) → both correct
        Assert.Equal(2, LiveScoring.Score(q, new LiveRoom.Answer { Pairs = new[] { 1, 0 }, Ts = 1 }, [], shuffledValues, 1));
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Pairs = new[] { 0, 1 }, Ts = 1 }, [], shuffledValues, 1));
    }

    [Fact]
    public void TypeAnswer_alias_matches()
    {
        var q = new Question { Id = "q", Prompt = "P", Options = new[] { "Paris" }, CategoryId = "mixed", Accepted = new[] { "Paris" } };
        Assert.Equal(3, LiveScoring.Score(q, new LiveRoom.Answer { Text = "  the paris ", Ts = 1 }, [], [], 3)); // normalized
        Assert.Equal(0, LiveScoring.Score(q, new LiveRoom.Answer { Text = "London", Ts = 1 }, [], [], 3));
    }

    [Fact]
    public void Enumerate_counts_unique_members()
    {
        var q = new Question
        {
            Id = "q", Prompt = "P", Options = [], CategoryId = "mixed",
            Enumerate = new EnumSpec { Groups = new IReadOnlyList<string>[] { new[] { "France" }, new[] { "Spain" } } },
        };
        Assert.Equal(1, LiveScoring.Score(q, new LiveRoom.Answer { List = new[] { "france", "germany" }, Ts = 1 }, [], [], 1));
        Assert.Equal(2, LiveScoring.Score(q, new LiveRoom.Answer { List = new[] { "France", "spain", "France" }, Ts = 1 }, [], [], 1));
    }
}
