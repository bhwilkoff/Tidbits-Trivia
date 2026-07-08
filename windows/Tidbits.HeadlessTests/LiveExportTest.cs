using System.Collections.Generic;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

public class LiveExportTest
{
    [Fact]
    public void Standings_csv_ranks_and_escapes()
    {
        var standings = new List<LiveHostNet.Joined>
        {
            new("u1", "Quiz Khalifa", 120),
            new("u2", "Les, Quizerables", 90),   // comma in the name
            new("u3", "The \"Best\"", 60),         // quotes in the name
        };
        var csv = LiveExport.StandingsCsv(standings);
        var expected =
            "Rank,Team,Score\n" +
            "1,\"Quiz Khalifa\",120\n" +
            "2,\"Les, Quizerables\",90\n" +
            "3,\"The \"\"Best\"\"\",60\n";
        Assert.Equal(expected, csv);
    }

    [Fact]
    public void Empty_standings_is_header_only()
    {
        Assert.Equal("Rank,Team,Score\n", LiveExport.StandingsCsv(new List<LiveHostNet.Joined>()));
    }
}
