using System.Collections.Generic;
using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A2.15 / 3.83 — how far a table moved since the last round's scoreboard.
/// Byte-identical to Swift's LiveStandingsMoveTests.
public class LiveStandingsMoveTest
{
    [Fact]
    public void A_table_that_climbs_reads_as_a_climb()
    {
        var m = LiveStandingsMove.Moves(new[] { "A", "B", "C", "D" }, new[] { "D", "A", "B", "C" });
        Assert.Equal(LiveStandingsMove.Move.Up(3), m["D"]);
        Assert.Equal(LiveStandingsMove.Move.Down(1), m["A"]);
        Assert.Equal(LiveStandingsMove.Move.Down(1), m["C"]);
    }

    [Fact]
    public void Nobody_moving_says_so_rather_than_nothing()
    {
        var m = LiveStandingsMove.Moves(new[] { "A", "B" }, new[] { "A", "B" });
        Assert.Equal(LiveStandingsMove.Move.Same, m["A"]);
        Assert.Null(LiveStandingsMove.BiggestClimb(m));   // a quiet round is quiet
    }

    [Fact]
    public void A_table_that_joined_mid_night_is_new()
    {
        var m = LiveStandingsMove.Moves(new[] { "A" }, new[] { "A", "Latecomers" });
        Assert.Equal(LiveStandingsMove.Move.New, m["Latecomers"]);
        Assert.Equal("NEW", LiveStandingsMove.Label(m["Latecomers"]));
    }

    [Fact]
    public void The_chip_reads_the_way_the_room_does()
    {
        Assert.Null(LiveStandingsMove.Label(null));   // the FIRST scoreboard says nothing
        Assert.Equal("—", LiveStandingsMove.Label(LiveStandingsMove.Move.Same));
        Assert.Equal("▲2", LiveStandingsMove.Label(LiveStandingsMove.Move.Up(2)));
        Assert.Equal("▼1", LiveStandingsMove.Label(LiveStandingsMove.Move.Down(1)));
    }

    [Fact]
    public void The_biggest_climb_is_named_once_and_deterministically()
    {
        var m = LiveStandingsMove.Moves(new[] { "A", "B", "C", "D" }, new[] { "C", "D", "A", "B" });
        Assert.Equal("Biggest climb: C up 2", LiveStandingsMove.BiggestClimb(m));
        var tie = new Dictionary<string, LiveStandingsMove.Move>
        {
            ["Zed"] = LiveStandingsMove.Move.Up(2), ["Amy"] = LiveStandingsMove.Move.Up(2),
        };
        Assert.Equal("Biggest climb: Amy up 2", LiveStandingsMove.BiggestClimb(tie));
    }

    [Fact]
    public void A_duplicate_name_keeps_its_best_previous_rank()
    {
        var m = LiveStandingsMove.Moves(new[] { "A", "A", "B" }, new[] { "A", "B" });
        Assert.Equal(LiveStandingsMove.Move.Same, m["A"]);
        Assert.Equal(LiveStandingsMove.Move.Up(1), m["B"]);
    }
}
