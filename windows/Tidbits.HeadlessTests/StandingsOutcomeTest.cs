using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A shared question set makes ties ordinary, not exotic: identical play earns
/// identical scores. Announcing element 0 of a score-sort as "the winner" turned
/// an arbitrary tiebreak into a declared victory, so the rule is pinned here.
public class StandingsOutcomeTest
{
    static List<(string, int)> E(params (string, int)[] xs) => xs.ToList();

    [Fact]
    public void Single_leader_wins()
        => Assert.Equal("Ana wins!", StandingsOutcome.Headline(E(("Ana", 900), ("Bo", 400)), "none"));

    [Fact]
    public void Everyone_level_is_a_tie()
        => Assert.Equal("It's a tie!", StandingsOutcome.Headline(E(("Ana", 900), ("Bo", 900)), "none"));

    [Fact]
    public void Partial_tie_names_the_leaders()
        => Assert.Equal("Tie — Ana & Bo", StandingsOutcome.Headline(E(("Ana", 900), ("Bo", 900), ("Cy", 100)), "none"));

    [Fact]
    public void Empty_board_uses_the_fallback()
        => Assert.Equal("Final scores", StandingsOutcome.Headline(E(), "Final scores"));

    [Fact]
    public void Every_tied_leader_is_highlighted()
    {
        var e = E(("Ana", 900), ("Bo", 900), ("Cy", 100));
        Assert.True(StandingsOutcome.IsTop(900, e));
        Assert.False(StandingsOutcome.IsTop(100, e));
        Assert.Equal(2, StandingsOutcome.Winners(e).Count);
    }

    [Fact]
    public void A_zero_zero_board_still_ties_rather_than_crowning()
        => Assert.Equal("It's a tie!", StandingsOutcome.Headline(E(("Ana", 0), ("Bo", 0)), "none"));
}
