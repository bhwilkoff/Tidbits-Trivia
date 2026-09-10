using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A8.11 — the big screen's "answers in" line. Byte-for-byte the Swift `LiveProgressTests`.
public class LiveProgressTest
{
    [Fact]
    public void An_empty_lobby_shows_nothing() => Assert.Null(LiveProgress.AnswersIn(0, 0));

    [Fact]
    public void It_counts_tables_in_and_out()
    {
        Assert.Equal("0 of 8 answered", LiveProgress.AnswersIn(0, 8));
        Assert.Equal("3 of 8 answered", LiveProgress.AnswersIn(3, 8));
        Assert.Equal("8 of 8 answered", LiveProgress.AnswersIn(8, 8));
    }

    [Fact]
    public void A_count_that_overruns_is_clamped()
    {
        Assert.Equal("8 of 8 answered", LiveProgress.AnswersIn(9, 8));
        Assert.Equal("0 of 8 answered", LiveProgress.AnswersIn(-1, 8));
    }
}
