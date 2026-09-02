using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G4 — the first-letter round. The SAME cases as Swift
/// TidbitsTriviaTests/LiveLetterRoundTests.swift: a Windows host and a Mac host
/// reading the same event file must theme it identically, and the only way that
/// stays true is if both stacks are pinned by the same judgement calls.
public class LiveLetterRoundTest
{
    private static Question Q(string answer, string id = "t1") => new()
    {
        Id = id, Prompt = "p", Options = new[] { answer, "x", "y", "z" },
        CorrectIndex = 0, CategoryId = "history", Difficulty = 2,
    };

    [Fact]
    public void A_plain_answer_takes_its_own_first_letter() =>
        Assert.Equal('B', LiveLetterRound.Initial("Budapest"));

    [Fact]
    public void A_leading_article_does_not_count()
    {
        Assert.Equal('B', LiveLetterRound.Initial("The Beatles"));
        Assert.Equal('C', LiveLetterRound.Initial("A Clockwork Orange"));
        Assert.Equal('I', LiveLetterRound.Initial("An Inspector Calls"));
    }

    [Fact]
    public void An_answer_that_is_only_an_article_still_resolves() =>
        Assert.Equal('T', LiveLetterRound.Initial("The"));

    [Fact]
    public void Diacritics_fold()
    {
        Assert.Equal('E', LiveLetterRound.Initial("Édith Piaf"));
        Assert.Equal('A', LiveLetterRound.Initial("Ångström"));
    }

    [Fact]
    public void An_answer_with_no_letter_belongs_to_no_round()
    {
        Assert.Null(LiveLetterRound.Initial("2001"));
        Assert.Null(LiveLetterRound.Initial(""));
        Assert.Null(LiveLetterRound.Initial("!!!"));
    }

    [Fact]
    public void Punctuation_before_the_first_letter_is_skipped() =>
        Assert.Equal('R', LiveLetterRound.Initial("'Round Midnight"));

    [Fact]
    public void Matching_is_case_insensitive_on_the_requested_letter()
    {
        Assert.True(LiveLetterRound.Matches(Q("Berlin"), 'b'));
        Assert.True(LiveLetterRound.Matches(Q("Berlin"), 'B'));
    }

    [Fact]
    public void Violations_name_exactly_the_questions_that_break_the_theme()
    {
        var qs = new[] { Q("Berlin", "a"), Q("Cairo", "b"), Q("The Bahamas", "c") };
        Assert.Equal(new[] { "b" }, LiveLetterRound.Violations(qs, 'B').Select(q => q.Id));
    }

    [Fact]
    public void Candidates_respect_the_cap_and_keep_pool_order()
    {
        var pool = new[] { Q("Berlin", "a"), Q("Cairo", "b"), Q("Boston", "c"), Q("Bogota", "d") };
        Assert.Equal(new[] { "a", "c" }, LiveLetterRound.Candidates(pool, 'B', 2).Select(q => q.Id));
    }

    [Fact]
    public void A_repeated_answer_is_not_offered_twice()
    {
        var pool = new[] { Q("Berlin", "a"), Q("berlin", "b"), Q("Boston", "c") };
        Assert.Equal(new[] { "a", "c" }, LiveLetterRound.Candidates(pool, 'B', 3).Select(q => q.Id));
    }

    [Fact]
    public void Availability_counts_what_each_letter_could_fill()
    {
        var pool = new[] { Q("Berlin", "a"), Q("Boston", "b"), Q("Cairo", "c"), Q("2001", "d") };
        var counts = LiveLetterRound.Availability(pool);
        Assert.Equal(2, counts['B']);
        Assert.Equal(1, counts['C']);
        Assert.False(counts.ContainsKey('Z'));
    }

    [Fact]
    public void The_banner_tells_the_room_the_rule_in_one_line() =>
        Assert.Equal("EVERY ANSWER BEGINS WITH B", LiveLetterRound.Banner('b'));

    [Fact]
    public void A_round_with_no_letter_theme_reports_none()
    {
        var ev = new LiveEvent { RoundLetters = new[] { "B", "" } };
        Assert.Equal('B', ev.LetterFor(0));
        Assert.Null(ev.LetterFor(1));
        Assert.Null(ev.LetterFor(9));   // out of range, not a crash
    }
}
