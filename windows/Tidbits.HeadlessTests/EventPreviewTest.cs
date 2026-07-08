using System.Collections.Generic;
using System.IO;
using System.Linq;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

/// An authored LiveEvent converts to a plan that draws real questions and plays
/// through the engine — the basis for the host's solo preview (3.13).
public class EventPreviewTest
{
    [Fact]
    public async Task Authored_event_previews_through_the_engine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Data"));
        var provider = new QuestionProvider(sources);

        var ev = new LiveEvent
        {
            Name = "Preview Night",
            Rounds = new List<NightRound>
            {
                new() { Kind = GameMode.Classic, Count = 3 },
                new() { Kind = GameMode.ThisOrThat, Count = 2 },
            },
        };
        var plan = ev.ToPlan();
        var questions = await provider.NightQuestions(plan, TriviaCategory.Named("mixed"));
        Assert.NotEmpty(questions);

        var engine = new GameEngine(provider, sources.Difficulty);
        engine.StartNight(plan, TriviaCategory.Named("mixed"), questions);

        // Drive every round + question to completion.
        int guard = 0, rounds = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 300)
        {
            switch (engine.CurrentPhase)
            {
                case GameEngine.Phase.RoundIntro: rounds++; engine.StartRound(); break;
                case GameEngine.Phase.Playing:
                    var q = engine.Current!;
                    if (q.Closest is not null) engine.SubmitGuess();
                    else if (q.Accepted is not null) engine.SubmitText();
                    else if (q.Ordering is not null) engine.SubmitOrder();
                    else if (q.Matching is not null) engine.SubmitMatch();
                    else if (q.Enumerate is not null) engine.FinishEnum();
                    else engine.Submit(q.CorrectIndex);
                    break;
                case GameEngine.Phase.Reveal: engine.Advance(); break;
            }
        }

        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.Equal(2, rounds);   // both authored rounds ran
    }
}
