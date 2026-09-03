using System.Collections.Generic;
using System.IO;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Windows FILE EDGE — build the artefact, write it, and read back what
/// landed.
///
/// HostMaterialsTest already covers the HTML a host prints. What nothing covered
/// was the write: the cockpit built a page, put it in temp and handed it to the
/// browser, and no test ever looked at the file. That is the same gap the macOS
/// panels had, and it is where a host's evening actually goes wrong — an empty
/// or missing file is indistinguishable from a working one until they open it.
public class LiveFileEdgeTest
{
    private static string Dir()
    {
        var d = Path.Combine(Path.GetTempPath(), "tidbits-fileedge");
        Directory.CreateDirectory(d);
        return d;
    }

    private static Question Q(string id, string prompt, string answer) => new()
    {
        Id = id, Prompt = prompt, Options = new[] { answer, "Wrong a", "Wrong b", "Wrong c" },
        CorrectIndex = 0, CategoryId = "history", Difficulty = 3, RoundIndex = 0,
    };

    [Fact]
    public void The_question_pack_is_written_and_carries_the_answers_the_host_reads()
    {
        var questions = new List<Question>
        {
            Q("p1", "Which Iron Age kingdom minted the world's oldest coins?", "Lydia"),
            Q("p2", "In which year was the Battle of Hastings fought?", "1066"),
        };
        var html = LiveExport.QuestionPackHtml("Friday Pub Quiz", questions);
        var path = LiveExport.WritePrintable(html, "pack.html", Dir());

        // The FILE, not the string the app built.
        Assert.True(File.Exists(path));
        var written = File.ReadAllText(path);
        Assert.True(written.Length > 200, $"the pack is only {written.Length} chars");

        // The host's copy must carry the answers he reads out.
        Assert.Contains("Answer: Lydia", written);
        Assert.Contains("Answer: 1066", written);
    }

    [Fact]
    public void The_team_answer_sheet_is_written_and_leaks_no_answer()
    {
        var rounds = new List<NightRound>
        {
            new() { Kind = GameMode.Classic, Count = 3 },
            new() { Kind = GameMode.Classic, Count = 2 },
        };
        var html = LiveExport.AnswerSheetHtml("Friday Pub Quiz", rounds);
        var path = LiveExport.WritePrintable(html, "sheet.html", Dir());

        var written = File.ReadAllText(path);
        Assert.True(File.Exists(path));
        // This is the one that matters: a leak here hands the room the answers.
        // Asserted on the written FILE, matching the macOS pdftotext check.
        Assert.DoesNotContain("Answer:", written);
        Assert.Contains("Team name:", written);
    }

    [Fact]
    public void The_standings_CSV_is_written_and_round_trips_through_a_reader()
    {
        var standings = new List<LiveHostNet.Joined>
        {
            new("a", "The Quizzinators", 12),
            new("b", "Comma, Inc.", 9),
        };
        var csv = LiveExport.StandingsCsv(standings);
        var path = LiveExport.WritePrintable(csv, "standings.csv", Dir());

        var lines = File.ReadAllLines(path);
        Assert.True(lines.Length >= 3, "header plus one row per team");
        Assert.Contains("The Quizzinators", lines[1]);
        // A team name containing a comma must survive as ONE field, or every
        // column after it shifts and the export is quietly wrong.
        var commaRow = lines.First(l => l.Contains("Comma"));
        Assert.Contains("\"Comma, Inc.\"", commaRow);
    }
}
