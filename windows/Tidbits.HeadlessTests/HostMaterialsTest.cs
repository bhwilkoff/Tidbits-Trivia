using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The printable host materials (audit A.3, macOS `LivePrint` parity): the teams' blank
/// answer sheet and the host's question pack. Pure string builders, so they unit-test.
public class HostMaterialsTest
{
    private static Question Q(string prompt, string answer, int round) => new()
    {
        Id = prompt, Prompt = prompt, Options = new[] { answer, "b", "c", "d" },
        CorrectIndex = 0, CategoryId = "mixed", Difficulty = 3, RoundIndex = round,
    };

    [Fact]
    public void Answer_sheet_has_a_numbered_line_per_question_and_no_answers()
    {
        var rounds = new List<NightRound>
        {
            new() { Kind = GameMode.Classic, Count = 3 },
            new() { Kind = GameMode.Classic, Count = 2 },
        };
        var html = LiveExport.AnswerSheetHtml("Pub Night", rounds);

        Assert.Contains("Pub Night", html);
        Assert.Contains("Team name:", html);
        Assert.Contains("Round 1:", html);
        Assert.Contains("Round 2:", html);
        // One blank line per question across both rounds (plus the team-name rule).
        Assert.Equal(3 + 2 + 1, System.Text.RegularExpressions.Regex.Matches(html, "class=\"rule\"").Count);

        // The name of this test claims "no answers" and nothing used to check it.
        // Today AnswerSheetHtml only receives round KIND + COUNT, so a leak is
        // impossible by signature — but that is an argument that could stop being
        // true the moment someone passes questions in, and the test would go on
        // claiming a property it never asserted.
        Assert.DoesNotContain("Answer:", html);
    }

    [Fact]
    public void Question_pack_lists_every_question_with_its_answer_grouped_by_round()
    {
        var qs = new List<Question> { Q("First?", "Alpha", 0), Q("Second?", "Beta", 0), Q("Third?", "Gamma", 1) };
        var html = LiveExport.QuestionPackHtml("Quiz Night", qs);

        Assert.Contains("Quiz Night", html);
        Assert.Contains("3 questions", html);
        foreach (var (prompt, answer) in new[] { ("First?", "Alpha"), ("Second?", "Beta"), ("Third?", "Gamma") })
        {
            Assert.Contains(prompt, html);
            Assert.Contains($"Answer: {answer}", html);
        }
        Assert.Contains("<h2>Round 1</h2>", html);
        Assert.Contains("<h2>Round 2</h2>", html);
    }

    /// A team name or prompt with markup must not break the page (or inject into it).
    [Fact]
    public void Printable_pages_escape_html()
    {
        var html = LiveExport.QuestionPackHtml("A & B <script>", new List<Question> { Q("2 < 3?", "yes", 0) });
        Assert.DoesNotContain("<script>", html);
        Assert.Contains("A &amp; B", html);
        Assert.Contains("2 &lt; 3?", html);
    }
}
