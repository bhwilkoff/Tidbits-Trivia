using System.IO;
using System.Linq;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Spaced re-asking: missed questions become "due", get woven into a later MCQ
/// game, and resolve once answered correctly.
public class SpacedReviewTest
{
    [Fact]
    public async Task Missed_question_is_rewoven_then_resolved_on_a_correct_answer()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(System.AppContext.BaseDirectory, "Fixtures"));
        var provider = new QuestionProvider(sources);
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-review-{System.Guid.NewGuid():N}.json");
        var store = new RecordsStore(path);
        try
        {
            // Game 1 — answer everything WRONG so questions become due for review.
            var e1 = new GameEngine(provider, sources.Difficulty);
            await e1.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
            DriveWrong(e1);
            store.Record(e1.Summary);

            var due = store.DueReview();
            Assert.NotEmpty(due);
            var reviewId = due[0].Id;

            // Game 2 — start WITH the review list; the due question is woven in.
            var e2 = new GameEngine(provider, sources.Difficulty);
            await e2.Start(GameMode.Classic, TriviaCategory.Named("mixed"), review: store.DueReview());
            Assert.Contains(e2.Questions, q => q.Id == reviewId);

            // Answer the review question CORRECTLY (others wrong) → it should resolve.
            while (e2.CurrentPhase != GameEngine.Phase.Finished)
            {
                if (e2.CurrentPhase == GameEngine.Phase.Playing && e2.Current is { } q)
                    e2.Submit(q.Id == reviewId ? q.CorrectIndex : (q.CorrectIndex + 1) % q.Options.Count);
                else if (e2.CurrentPhase == GameEngine.Phase.Reveal) e2.Advance();
            }
            store.Record(e2.Summary);

            Assert.DoesNotContain(store.DueReview(20), q => q.Id == reviewId); // resolved
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    private static void DriveWrong(GameEngine e)
    {
        int guard = 0;
        while (e.CurrentPhase != GameEngine.Phase.Finished && guard++ < 40)
        {
            if (e.CurrentPhase == GameEngine.Phase.Playing && e.Current is { } q)
                e.Submit((q.CorrectIndex + 1) % q.Options.Count);
            else if (e.CurrentPhase == GameEngine.Phase.Reveal) e.Advance();
        }
    }
}
