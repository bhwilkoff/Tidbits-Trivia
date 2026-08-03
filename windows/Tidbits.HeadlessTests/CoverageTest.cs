using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Coverage disclosure (PARITY: "a mode can't fill a category"). A mode x category the
/// bundle cannot fill still PLAYS — it is assembled from other categories — so the picker
/// has to say so before the player commits. These pin the rule itself, not the chrome.
public class CoverageTest
{
    private static QuestionSources Sources() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));

    [Fact]
    public void Mixed_always_fills()
    {
        var s = Sources();
        Assert.True(s.CanFill(GameMode.PictureId, "mixed"));
        Assert.Equal(int.MaxValue, s.Coverage(GameMode.Classic, "mixed"));
    }

    [Fact]
    public void A_category_with_no_rows_in_a_shape_set_cannot_fill_it()
    {
        var s = Sources();
        // The rule is arithmetic, not a guess: coverage below the mode's question count
        // is exactly what "will be assembled from other categories" means.
        foreach (var mode in new[] { GameMode.PictureId, GameMode.ThisOrThat, GameMode.Matching })
        {
            foreach (var cat in TriviaCategory.All)
            {
                Assert.Equal(s.Coverage(mode, cat.Id) >= mode.QuestionCount(), s.CanFill(mode, cat.Id));
            }
        }
    }

    [Fact]
    public void Coverage_counts_only_the_named_category()
    {
        var s = Sources();
        var perCat = TriviaCategory.All.Where(c => c.Id != "mixed")
            .Sum(c => s.Coverage(GameMode.ThisOrThat, c.Id));
        // Every row belongs to exactly one category, so the per-category counts cannot
        // exceed the set — a bug that counted "mixed" per chip would blow straight past.
        Assert.True(perCat <= s.Enrich(GameMode.ThisOrThat).Count);
    }
}
