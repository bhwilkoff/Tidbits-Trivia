using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Create's promise is "pick any subject and we build you a quiz about it".
/// Diversify round-robins by CATEGORY, so before the matched-token tier existed a
/// one-word coincidence in an under-filled category got PROMOTED over a genuine
/// hit — typing "Marie Curie" led with "In what year was Marie de' Medici born?".
public class CreateRelevanceTest
{
    static Question Q(string id, string cat, string prompt, string answer = "zzz") => new()
    {
        Id = id, Prompt = prompt, SourceTitle = prompt, Explanation = prompt,
        CategoryId = cat, Difficulty = 3,
        Options = [answer, "a", "b", "c"], CorrectIndex = 0, Tags = [],
    };

    /// The cap must not throttle a genuinely single-domain result set.
    [Fact]
    public void Diversify_fills_the_limit_even_when_every_hit_is_one_category()
    {
        var ranked = Enumerable.Range(0, 20)
            .Select(i => Q($"s{i}", "science", $"science question {i}")).ToList();
        var got = CorpusDatabase.Diversify(ranked, 8);
        Assert.Equal(8, got.Count);
        Assert.Equal(8, got.Select(q => q.Id).Distinct().Count());
    }

    /// With several categories available it still spreads rather than taking the
    /// top 8 of one lane — the anti-monopoly rule is preserved.
    [Fact]
    public void Diversify_still_spreads_across_categories_when_it_can()
    {
        var ranked = new List<Question>();
        foreach (var cat in new[] { "science", "history", "music" })
            for (int i = 0; i < 10; i++) ranked.Add(Q($"{cat}{i}", cat, $"{cat} question {i}"));
        var got = CorpusDatabase.Diversify(ranked, 9);
        Assert.Equal(9, got.Count);
        Assert.True(got.Select(q => q.CategoryId).Distinct().Count() >= 3);
    }

    [Fact]
    public void Diversify_returns_everything_when_the_pool_is_smaller_than_the_limit()
    {
        var ranked = new List<Question> { Q("a", "science", "one"), Q("b", "history", "two") };
        Assert.Equal(2, CorpusDatabase.Diversify(ranked, 8).Count);
    }

    [Fact]
    public void Diversify_of_an_empty_pool_is_empty()
        => Assert.Empty(CorpusDatabase.Diversify([], 8));
}
