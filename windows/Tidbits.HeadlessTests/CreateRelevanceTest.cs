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

/// The relevance FLOOR, measured by play-testing the 984 most-viewed Wikipedia
/// articles through the shipped Apple assembly on the simulator: 49.8% of every
/// question Create served was about something other than what the player typed.
/// Each case below is one of the measured failures. Mirrors the Swift
/// CreateTopicDriftTests and tools/create/web-mirror-check.mjs — if these three
/// disagree, the same topic returns a different quiz per platform.
public class CreateTopicDriftTest
{
    static int? Tier(string title, string topic, string prompt = "",
                     string[]? tags = null, bool guardNames = false)
        => QueryHelpers.Tier(title, prompt, tags ?? [], QueryHelpers.Tokenize(topic),
                             QueryHelpers.TopicPhrase(topic), guardNames,
                             QueryHelpers.PhraseIsRequired(topic));

    [Fact]
    public void A_word_inside_a_longer_word_is_not_a_match()
    {
        Assert.True(QueryHelpers.ContainsWord("art deco", "art"));
        Assert.False(QueryHelpers.ContainsWord("mozart", "art"));
        Assert.False(QueryHelpers.ContainsWord("hansel and gretel", "ansel"));
        Assert.False(QueryHelpers.ContainsWord("spokane washington", "kane"));
        Assert.False(QueryHelpers.ContainsWord("indianapolis", "india"));
    }

    [Fact]
    public void A_topic_the_corpus_does_not_know_is_rejected_rather_than_approximated()
    {
        Assert.Null(Tier("Spokane, Washington", "Harry Kane"));
        Assert.Null(Tier("Butane", "Harry Kane"));
        Assert.Null(Tier("Harry Potter and the Cursed Child", "Harry Kane"));
    }

    [Fact]
    public void A_different_person_whose_name_contains_the_place_is_rejected()
    {
        Assert.Null(Tier("Bob Denver", "Denver", guardNames: true));
        Assert.Null(Tier("Denver Pyle", "Denver", guardNames: true));
        Assert.NotNull(Tier("Denver International Airport", "Denver", guardNames: true));
    }

    /// ...and only then. "Potter" is not a subject in its own right, so a player
    /// typing it means Harry Potter and must not be left with nothing.
    [Fact]
    public void The_surname_guard_does_not_fire_when_the_word_is_not_its_own_subject()
        => Assert.NotNull(Tier("Harry Potter", "Potter"));

    /// No Wikipedia category admits a row on its own any more — not the incidental
    /// kind, and not the agentive kind, which was the last source of drift.
    [Fact]
    public void No_category_tag_admits_a_row_on_its_own()
    {
        Assert.Null(Tier("Thriller (album)", "Michael Jackson",
                         tags: ["Albums produced by Michael Jackson"]));
        Assert.Null(Tier("Kristin Cavallari", "Denver", tags: ["Actresses from Denver"]));
        Assert.Null(Tier("Neil Sedaka", "Abraham Lincoln",
                         tags: ["Abraham Lincoln High School (Brooklyn) alumni"]));
    }

    /// A tag connection is real but INVISIBLE, so it no longer admits a row —
    /// "Rod Stewart" produced Britt Ekland's height off a "Partners of" tag.
    [Fact]
    public void An_agentive_tag_alone_no_longer_admits_a_row()
    {
        Assert.Null(Tier("Bad (album)", "Michael Jackson",
                         tags: ["Albums produced by Michael Jackson"]));
        Assert.Null(Tier("Britt Ekland", "Rod Stewart", tags: ["Partners of Rod Stewart"]));
    }

    /// ...while the same album survives when the question NAMES him.
    [Fact]
    public void The_same_row_survives_when_the_prompt_names_the_topic()
        => Assert.Equal(0, Tier("Bad (album)", "Michael Jackson",
                                prompt: "Michael Jackson's seventh studio album"));

    [Fact]
    public void A_disambiguator_is_not_a_topic_word()
    {
        Assert.Equal("masters of the universe",
                     QueryHelpers.TopicPhrase("Masters of the Universe (2026 film)"));
        Assert.DoesNotContain("film", QueryHelpers.Tokenize("Backrooms (film)"));
    }

    /// The phrase keeps its stopwords and its order — the significant-token list
    /// can never reconstruct "masters of the universe".
    [Fact]
    public void The_phrase_survives_stopword_removal()
    {
        Assert.Equal("world war ii", QueryHelpers.TopicPhrase("World War II"));
        Assert.Equal(3, Tier("Masters of the Universe", "Masters of the Universe (2026 film)"));
    }

    /// A regnal numeral is short but not insignificant. Found by sweeping topics
    /// 301-984, which the first 300 never contained.
    [Fact]
    public void A_regnal_numeral_or_initial_forces_a_phrase_match()
    {
        Assert.True(QueryHelpers.PhraseIsRequired("George VI"));
        Assert.True(QueryHelpers.PhraseIsRequired("O. J. Simpson"));
        Assert.Null(Tier("George Martin", "George VI"));
        Assert.Null(Tier("Paul George", "George VI"));
        Assert.Null(Tier("Homer Simpson", "O. J. Simpson"));
        Assert.Equal(3, Tier("George VI", "George VI"));
    }

    /// ...and it must NOT fire when the dropped word is a mere stopword.
    [Fact]
    public void A_dropped_stopword_does_not_force_a_phrase_match()
    {
        Assert.False(QueryHelpers.PhraseIsRequired("The Beatles"));
        Assert.False(QueryHelpers.PhraseIsRequired("Denver"));
        Assert.NotNull(Tier("Abbey Road", "The Beatles", prompt: "the beatles recorded it here"));
    }

    /// A prompt occurrence inside a DIFFERENT proper name is not a match: "Denver"
    /// matched "...and John Denver", "Michael Jackson" a Glenda Jackson biopic.
    [Fact]
    public void A_name_inside_someone_elses_name_is_not_a_match()
    {
        var denver = QueryHelpers.Tokenize("Denver");
        Assert.False(QueryHelpers.PromptHasWord("Written by Bill Danoff and John Denver", "denver", denver));
        Assert.True(QueryHelpers.PromptHasWord("before Denver drafted him in 2024", "denver", denver));
        Assert.True(QueryHelpers.PromptHasWord("this Denver-based budget carrier", "denver", denver));
        var mj = QueryHelpers.Tokenize("Michael Jackson");
        Assert.False(QueryHelpers.PromptHasWord("marked Glenda Jackson's final role", "jackson", mj));
        Assert.True(QueryHelpers.PromptHasWord("Michael Jackson's seventh studio album", "jackson", mj));
    }

    /// ...and a capitalised predecessor the player TYPED is still a match.
    [Fact]
    public void A_capitalised_predecessor_the_user_typed_is_still_a_match()
        => Assert.True(QueryHelpers.PromptHasWord("Written by John Lennon and Paul McCartney",
            "mccartney", QueryHelpers.Tokenize("Paul McCartney")));

    /// Identity ignores the disambiguator: the corpus titles the rapper "Drake
    /// (musician)", so the guard never armed and "Drake" returned Nick Drake.
    [Fact]
    public void A_disambiguated_title_still_counts_as_the_subject()
    {
        Assert.Equal(3, Tier("Drake (musician)", "Drake"));
        Assert.Null(Tier("Nick Drake", "Drake", guardNames: true));
        Assert.Null(Tier("Drake & Josh", "Drake", guardNames: true));
    }

    /// ...while CONTAINMENT still reads the full title.
    [Fact]
    public void Containment_still_sees_the_disambiguator()
        => Assert.Equal(2, Tier("Dangerous (Michael Jackson album)", "Michael Jackson"));

    [Fact]
    public void The_subject_itself_outranks_a_containing_title()
    {
        Assert.Equal(3, Tier("Denver", "Denver"));
        Assert.Equal(2, Tier("Denver International Airport", "Denver"));
    }
}
