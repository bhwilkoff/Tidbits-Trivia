using Tidbits.Core.Data;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Diacritic folding is a CROSS-STACK contract: the corpus build writes a folded
/// `search_text` column, and Swift/Kotlin/C#/JS each fold at compare time. If any
/// one disagrees, the same topic returns different questions per platform. Before
/// this existed, "Beyonce" matched 0 of the 22 Beyoncé rows, "Bjork" 0 of 8 and
/// "Dvorak" 0 of 10 — a whole class of subjects was invisible to Create.
/// Mirrors TidbitsTriviaTests/CreateRelevanceTests.swift (FoldingTests).
public class FoldingTest
{
    [Theory]
    [InlineData("Beyoncé", "beyonce")]
    [InlineData("Björk", "bjork")]
    [InlineData("Antonín Dvořák", "antonin dvorak")]
    [InlineData("Zürich", "zurich")]
    [InlineData("Chloë", "chloe")]
    public void Accents_are_stripped_and_case_lowered(string input, string expected)
        => Assert.Equal(expected, QueryHelpers.Fold(input));

    [Fact]
    public void Plain_ascii_is_unchanged_apart_from_case()
    {
        Assert.Equal("the beatles", QueryHelpers.Fold("The Beatles"));
        Assert.Equal("beyonce", QueryHelpers.Fold(QueryHelpers.Fold("Beyoncé")));
    }

    [Fact]
    public void Folding_matches_in_either_direction()
        => Assert.Equal(QueryHelpers.Fold("beyoncé"), QueryHelpers.Fold("BEYONCÉ"));

    /// Windows shipped the pre-filter cap fix but never the stopword drop, so
    /// "The Beatles" still flooded its candidate pool with rows matching "the"
    /// while Apple/Android/web did not — the same topic, two different quizzes.
    [Fact]
    public void Stopwords_are_dropped_from_the_query()
    {
        Assert.Equal(new[] { "beatles" }, QueryHelpers.Tokenize("The Beatles"));
        Assert.Equal(new[] { "simpsons" }, QueryHelpers.Tokenize("The Simpsons"));
        Assert.Equal(new[] { "beyonce" }, QueryHelpers.Tokenize("Beyoncé"));
    }

    /// A topic made only of stopwords must still search for something rather than
    /// returning nothing at all.
    [Fact]
    public void A_topic_of_only_stopwords_falls_back_to_the_raw_tokens()
        => Assert.Equal(new[] { "the", "and" }, QueryHelpers.Tokenize("The and"));
}
