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

    [Fact]
    public void Standings_html_is_printable_and_escapes()
    {
        var standings = new List<LiveHostNet.Joined>
        {
            new("u1", "Quiz Khalifa", 120),
            new("u2", "<script>", 30),   // must be escaped, not injected
        };
        var html = LiveExport.StandingsHtml(standings, "Friday Night");
        Assert.StartsWith("<!doctype html>", html);
        Assert.Contains("<h1>Friday Night</h1>", html);
        Assert.Contains("<td>Quiz Khalifa</td>", html);
        Assert.Contains("&lt;script&gt;", html);        // escaped
        Assert.DoesNotContain("<script>", html);         // not injected
    }
}
