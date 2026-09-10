using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A3.13 / 3.72: a key fixed after reveal re-scores; a prompt typo fix must not.
public class RescoreTest
{
    private static Question Q() => new()
    {
        Id = "q1", Prompt = "Who played Neo?", Options = new[] { "Keanu Reeves", "B", "C", "D" }, CorrectIndex = 0,
        CategoryId = "film", Difficulty = 4, Explanation = "", SourceTitle = "", TemplateId = "hand", Accepted = new[] { "Keanu Reeves" },
    };

    [Fact]
    public void A_prompt_or_story_edit_is_not_a_key_change()
    {
        Assert.False(LiveScoring.KeyDiffers(Q(), Q() with { Prompt = "Who played Neo in The Matrix?" }));
        Assert.False(LiveScoring.KeyDiffers(Q(), Q() with { Explanation = "He did.", SourceTitle = "Keanu Reeves" }));
        Assert.False(LiveScoring.KeyDiffers(Q(), Q() with { Accepted = new[] { "Keanu Reeves" } }));   // same list, new instance
    }

    [Fact]
    public void The_accepted_list_the_correct_index_and_the_options_are_the_key()
    {
        Assert.True(LiveScoring.KeyDiffers(Q(), Q() with { Accepted = new[] { "Neo" } }));
        Assert.True(LiveScoring.KeyDiffers(Q(), Q() with { Accepted = new[] { "Keanu Reeves", "Keanu" } }));
        Assert.True(LiveScoring.KeyDiffers(Q(), Q() with { CorrectIndex = 1 }));
        Assert.True(LiveScoring.KeyDiffers(Q(), Q() with { Options = new[] { "B", "Keanu Reeves", "C", "D" } }));
        Assert.True(LiveScoring.KeyDiffers(Q(), Q() with { Closest = new ClosestSpec { Answer = 1999, Min = 1990, Max = 2010, Step = 1, Tolerance = 1, Unit = "" } }));
    }
}
