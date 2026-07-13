using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

/// Track A: a category × type coverage hole must never yield an empty round.
public class QuestionFallbackTest
{
    // Fresh provider each test → no shared seen-set pollution.
    private static QuestionProvider Fresh() => new(Tidbits.App.Services.GameData.Shared.Value.Sources);

    [Fact]
    public async Task Matching_sports_hole_fills_a_full_round()
    {
        // match.json has ZERO sports rows — the reported bug. Must now fall back
        // to the whole Match Up pool and return a FULL round, not empty.
        var qs = await Fresh().Questions(GameMode.Matching, TriviaCategory.Named("sports"));
        Assert.NotEmpty(qs);
        Assert.Equal(GameMode.Matching.QuestionCount(), qs.Count);
    }

    [Fact]
    public async Task Every_category_x_special_type_is_nonempty()
    {
        var cats = new[] { "arts", "geography", "history", "music", "science", "screen", "sports" };
        var types = new[]
        {
            GameMode.PictureId, GameMode.ThisOrThat, GameMode.ClosestCall,
            GameMode.Ordering, GameMode.Matching, GameMode.TypeAnswer,
            GameMode.OddOneOut, GameMode.Enumerate,
        };
        foreach (var t in types)
            foreach (var c in cats)
            {
                var qs = await Fresh().Questions(t, TriviaCategory.Named(c));
                Assert.True(qs.Count > 0, $"EMPTY round for {t} × {c} — the load bug");
            }
    }
}
