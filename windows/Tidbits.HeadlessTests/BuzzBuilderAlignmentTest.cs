using System.Collections.Generic;
using System.Linq;
using Avalonia.Headless.XUnit;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The buzz flags must stay attached to the RIGHT round.
///
/// `_buzz` is a list parallel to the rounds, like `_notes` and `_timers`. Every
/// add, move and delete has to shuffle it identically or a host's buzz flag ends
/// up on a different round — and they would only find out mid-night, when the
/// wrong round starts asking the room to buzz. The same index-parallel trap that
/// LIVE-EVENT-FILE §3.2 calls out for clip arrays.
public class BuzzBuilderAlignmentTest
{
    private static LiveEvent EventWithBuzzOn(int roundCount, params int[] buzzIndices)
    {
        var rounds = Enumerable.Range(0, roundCount)
            .Select(_ => new NightRound { Kind = GameMode.Classic, Count = 3 }).ToList();
        var buzz = Enumerable.Range(0, roundCount).Select(i => buzzIndices.Contains(i)).ToList();
        return new LiveEvent { Name = "n", Rounds = rounds, BuzzRounds = buzz };
    }

    [AvaloniaFact]
    public void Loading_an_event_keeps_each_flag_on_its_own_round()
    {
        var view = new LiveView();
        view.LoadEventForTesting(EventWithBuzzOn(3, 1));
        Assert.Equal(new[] { false, true, false }, view.BuzzFlagsForTesting.ToArray());
    }

    [AvaloniaFact]
    public void Moving_a_round_carries_its_buzz_flag_with_it()
    {
        var view = new LiveView();
        view.LoadEventForTesting(EventWithBuzzOn(3, 1));
        Assert.True(view.BuzzFlagsForTesting[1], "precondition: round 2 is the buzz round");

        view.MoveRoundForTesting(1, -1);          // the buzz round moves up
        Assert.Equal(new[] { true, false, false }, view.BuzzFlagsForTesting.ToArray());
    }
}
