using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The question editor is only real if what the host authored is what the room
/// plays. Before this, a Windows round was `{kind, count}` and `Start()` pulled a
/// fresh corpus round every time — so an editor could have shipped, looked
/// perfect, and had zero effect on the night. These assert the wiring, not the UI.
public class AuthoredQuestionsTest
{
    private static Question Q(string id, string prompt) => new()
    {
        Id = id, Prompt = prompt,
        Options = ["right", "wrong1", "wrong2", "wrong3"], CorrectIndex = 0,
        CategoryId = "history", Difficulty = 3, TemplateId = "hand",
    };

    private static QuestionProvider Provider() =>
        new(QuestionSources.LoadFromDirectory(
            System.IO.Path.Combine(System.AppContext.BaseDirectory, "Fixtures")));

    [Fact]
    public async Task A_fully_authored_event_plays_exactly_the_host_questions()
    {
        var authored = new List<Question> { Q("mine:1", "First"), Q("mine:2", "Second") };
        var ev = new LiveEvent
        {
            Name = "Authored",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 2 }],
            RoundQuestions = [authored],
        };
        var qs = await LiveNightHost.PreviewQuestions(ev.ToPlan(), ev, Provider(), TriviaCategory.Named("mixed"));

        Assert.Equal(2, qs.Count);
        Assert.Equal(new[] { "mine:1", "mine:2" }, qs.Select(q => q.Id));
        Assert.All(qs, q => Assert.Equal(0, q.RoundIndex));
    }

    [Fact]
    public async Task A_half_authored_event_keeps_the_corpus_for_the_other_round()
    {
        var authored = new List<Question> { Q("mine:1", "First") };
        var ev = new LiveEvent
        {
            Name = "Half",
            Rounds =
            [
                new NightRound { Kind = GameMode.Classic, Count = 1 },
                new NightRound { Kind = GameMode.Classic, Count = 3 },
            ],
            // Round 0 authored, round 1 left to the corpus.
            RoundQuestions = [authored, new List<Question>()],
        };
        var qs = await LiveNightHost.PreviewQuestions(ev.ToPlan(), ev, Provider(), TriviaCategory.Named("mixed"));

        Assert.Equal(4, qs.Count);
        Assert.Equal("mine:1", qs[0].Id);
        Assert.Equal(0, qs[0].RoundIndex);
        // The corpus questions must be tagged with their REAL plan position (1), not
        // the compacted index of the reduced plan the provider was asked for.
        Assert.All(qs.Skip(1), q => Assert.Equal(1, q.RoundIndex));
        Assert.All(qs.Skip(1), q => Assert.NotEqual("mine:1", q.Id));
    }

    [Fact]
    public async Task An_unauthored_event_is_unchanged()
    {
        var ev = new LiveEvent
        {
            Name = "Corpus",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 3 }],
        };
        var qs = await LiveNightHost.PreviewQuestions(ev.ToPlan(), ev, Provider(), TriviaCategory.Named("mixed"));
        Assert.Equal(3, qs.Count);
        Assert.All(qs, q => Assert.Equal(0, q.RoundIndex));
    }

    [Fact]
    public void Editing_a_round_keeps_its_count_in_step_with_its_questions()
    {
        // LIVE-EVENT-FILE §2.5. A count that outran the authored list would build a
        // night asking the provider to top up questions the host thought they had
        // replaced.
        var ev = new LiveEvent
        {
            Name = "Counts",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 5 }],
        };
        var edited = ev.WithQuestions(0, [Q("a", "A"), Q("b", "B")]);
        Assert.Equal(2, edited.Rounds[0].Count);
        Assert.Equal(2, edited.TotalQuestions);
        Assert.True(edited.IsFullyAuthored);
    }

    [Fact]
    public void An_event_with_no_authored_questions_is_not_fully_authored()
    {
        var ev = new LiveEvent { Rounds = [new NightRound { Kind = GameMode.Classic, Count = 5 }] };
        Assert.False(ev.IsFullyAuthored);
    }
}
