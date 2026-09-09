using System.Collections.Generic;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// 3.21 "accept this answer from everyone" — the ruling reaches exactly the
/// teams the scorer refused for THAT answer, each once. Mirrors the Swift suite.
public class TextReviewAcceptAllTest
{
    private static LiveRoom.Answer A(string text) => new() { Text = text, Ts = 1 };

    [Fact]
    public void Everyone_who_typed_the_same_thing_under_the_scorers_normalisation()
    {
        var answers = new Dictionary<string, LiveRoom.Answer>
        {
            ["t1"] = A("Keanu Reeves"), ["t2"] = A("keanu reeves"), ["t3"] = A("The Keanu Reeves!"),
            ["t4"] = A("Keanu Reaves"), ["t5"] = A("Kenau Reeves"),
        };
        var got = LiveNightHost.TypedAlike("Keanu Reeves", answers, new[] { "Reeves" }, new HashSet<string>());
        Assert.Equal(new[] { "t1", "t2", "t3" }, got);
    }

    [Fact]
    public void A_team_the_matcher_already_credited_is_not_paid_again()
    {
        var answers = new Dictionary<string, LiveRoom.Answer> { ["t1"] = A("Reeves"), ["t2"] = A("reeves") };
        Assert.Empty(LiveNightHost.TypedAlike("Reeves", answers, new[] { "Reeves" }, new HashSet<string>()));
    }

    [Fact]
    public void A_team_accepted_by_hand_earlier_is_not_paid_twice()
    {
        var answers = new Dictionary<string, LiveRoom.Answer> { ["t1"] = A("Keanu"), ["t2"] = A("keanu") };
        Assert.Equal(new[] { "t2" }, LiveNightHost.TypedAlike("Keanu", answers, new[] { "Reeves" }, new HashSet<string> { "t1" }));
    }

    [Fact]
    public void Blank_rulings_and_non_text_answers_match_nobody()
    {
        var answers = new Dictionary<string, LiveRoom.Answer> { ["t1"] = A("   "), ["t2"] = new() { Choice = 1, Ts = 1 } };
        Assert.Empty(LiveNightHost.TypedAlike("  ", answers, new string[0], new HashSet<string>()));
        Assert.Empty(LiveNightHost.TypedAlike("x", answers, new string[0], new HashSet<string>()));
    }
}
