using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A2.12 / 3.76 — the night is kept after the cockpit closes: newest first, capped,
/// and the report regenerates from the archived sheet rather than being stored.
public class NightArchiveTest
{
    private static string TempPath() =>
        System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tidbits-nights-" + System.Guid.NewGuid().ToString("N") + ".json");

    private static LiveAnswerRecord Rec(string qid, int right, int wrong)
    {
        var lines = new List<LiveAnswerRecord.Line>();
        for (int i = 0; i < right; i++) lines.Add(new LiveAnswerRecord.Line($"r{i}", $"Right {i}", "Keanu Reeves", 1));
        for (int i = 0; i < wrong; i++) lines.Add(new LiveAnswerRecord.Line($"w{i}", $"Wrong {i}", "Neo", 0));
        return new LiveAnswerRecord(qid, 1, 1, qid, "Keanu Reeves", lines);
    }

    [Fact]
    public void Nights_are_kept_newest_first_with_a_headline()
    {
        var a = new NightArchive(TempPath());
        a.Record("Tuesday", "The Anchor", new[]
        {
            new ArchivedNight.Row { Name = "The Quizzards", Score = 14 },
            new ArchivedNight.Row { Name = "Table 2", Score = 9, Paper = true },
        }, new[] { Rec("q1", 2, 0) });
        a.Record("Wednesday", "The Anchor", new[] { new ArchivedNight.Row { Name = "Solo", Score = 3 } }, System.Array.Empty<LiveAnswerRecord>());

        Assert.Equal(new[] { "Wednesday", "Tuesday" }, a.Nights.Select(n => n.Name));
        Assert.Equal("2 teams · The Quizzards won with 14", a.Nights[1].Headline);
        Assert.Equal("1 team · Solo won with 3", a.Nights[0].Headline);
        Assert.Equal("The Quizzards", a.Nights[1].Winner!.Name);
    }

    [Fact]
    public void An_empty_night_says_so_rather_than_naming_a_winner()
    {
        var a = new NightArchive(TempPath());
        var n = a.Record("Nobody came", "", System.Array.Empty<ArchivedNight.Row>(), System.Array.Empty<LiveAnswerRecord>());
        Assert.Equal("No teams were scored", n.Headline);
        Assert.Null(n.Winner);
    }

    /// audit-the-degenerate-outcome: a night where the host never revealed pays nobody, so
    /// crowning whoever sorted first is a lie. Found on the glass, tick 31.
    [Fact]
    public void Nobody_wins_a_night_where_nobody_scored()
    {
        var a = new NightArchive(TempPath());
        var n = a.Record("Unrevealed", "", new[]
        {
            new ArchivedNight.Row { Name = "Table 1", Score = 0 },
            new ArchivedNight.Row { Name = "Table 2", Score = 0 },
        }, System.Array.Empty<LiveAnswerRecord>());
        Assert.Equal("2 teams · nobody scored", n.Headline);
        Assert.Null(n.Winner);
    }

    [Fact]
    public void The_report_regenerates_from_the_archived_sheet()
    {
        var a = new NightArchive(TempPath());
        var n = a.Record("N", "", new[]
        {
            new ArchivedNight.Row { Name = "A", Score = 1 },
            new ArchivedNight.Row { Name = "B", Score = 0 },
        }, new[] { Rec("q1", 1, 1) });
        Assert.False(n.Report.IsEmpty);
        Assert.Single(n.Report.Questions);
        Assert.Equal("50%", LiveNightReport.Percent(n.Report.OverallAccuracy));
    }

    [Fact]
    public void The_archive_is_capped_and_survives_a_relaunch()
    {
        var path = TempPath();
        var a = new NightArchive(path);
        for (int i = 0; i <= NightArchive.Cap + 3; i++)
            a.Record($"N{i}", "", System.Array.Empty<ArchivedNight.Row>(), System.Array.Empty<LiveAnswerRecord>());
        Assert.Equal(NightArchive.Cap, a.Nights.Count);
        Assert.Equal($"N{NightArchive.Cap + 3}", a.Nights[0].Name);

        var again = new NightArchive(path);   // the host's archive outlives the launch
        Assert.Equal(NightArchive.Cap, again.Nights.Count);
        Assert.Equal(a.Nights[0].Name, again.Nights[0].Name);
        Assert.Equal(a.Nights[0].Id, again.Nights[0].Id);
        System.IO.File.Delete(path);
    }

    [Fact]
    public void Delete_forgets_one_night_and_a_runaway_sheet_is_trimmed()
    {
        var a = new NightArchive(TempPath());
        a.Record("Keep", "", System.Array.Empty<ArchivedNight.Row>(), System.Array.Empty<LiveAnswerRecord>());
        var gone = a.Record("Gone", "", System.Array.Empty<ArchivedNight.Row>(), System.Array.Empty<LiveAnswerRecord>());
        a.Delete(gone.Id);
        Assert.Equal(new[] { "Keep" }, a.Nights.Select(n => n.Name));

        var huge = Enumerable.Range(0, NightArchive.LogCap + 50).Select(i => Rec($"q{i}", 1, 0)).ToList();
        var big = a.Record("Long", "", new[] { new ArchivedNight.Row { Name = "A", Score = 1 } }, huge);
        Assert.Equal(NightArchive.LogCap, big.Log.Count);
    }
}
