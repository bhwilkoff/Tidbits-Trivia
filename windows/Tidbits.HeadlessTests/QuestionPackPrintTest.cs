using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The printable question pack — the Wi-Fi-dies fallback.
///
/// It used to be reachable only from a RUNNING cockpit, because a saved Windows
/// event stored {kind, count} and a pack printed from the builder would have listed
/// questions the room never sees. Now that an event carries its own questions it can
/// be printed before the night, which is the only time a contingency is useful.
public class QuestionPackPrintTest
{
    private static Question Q(string id, string prompt, string answer, int round) => new()
    {
        Id = id, Prompt = prompt, Options = [answer, "Wrong a", "Wrong b", "Wrong c"],
        CorrectIndex = 0, CategoryId = "history", Difficulty = 3, TemplateId = "test",
        RoundIndex = round,
    };

    [Fact]
    public void The_pack_carries_every_question_and_its_answer()
    {
        var questions = new List<Question>
        {
            Q("p:1", "This Iron Age kingdom minted the oldest coins", "Lydia", 0),
            Q("p:2", "In which year was the Battle of Hastings fought?", "1066", 0),
            Q("p:3", "Name that tune", "Bohemian Rhapsody", 1),
        };
        var html = LiveExport.QuestionPackHtml("Friday Pub Quiz", questions);

        Assert.Contains("Friday Pub Quiz", html);
        foreach (var q in questions)
        {
            Assert.Contains(q.Prompt, html);
            Assert.Contains(q.CorrectAnswer, html);   // the HOST's copy shows answers
        }
        // Rounds are separated, not run together into one list.
        Assert.Contains("Round 1", html);
        Assert.Contains("Round 2", html);
    }

    [Fact]
    public void The_team_answer_sheet_does_not_leak_the_answers()
    {
        var rounds = new List<NightRound>
        {
            new() { Kind = GameMode.Classic, Count = 2 },
            new() { Kind = GameMode.TypeAnswer, Count = 1 },
        };
        var html = LiveExport.AnswerSheetHtml("Friday Pub Quiz", rounds);

        Assert.Contains("Team name", html);
        Assert.Contains("Round 1", html);
        Assert.Contains("Round 2", html);
        Assert.DoesNotContain("Lydia", html);
        // One blank line per question, so the sheet matches the night's length.
        Assert.Equal(3, html.Split("<li>").Length - 1);
    }

    [Fact]
    public void Html_escapes_a_prompt_that_contains_markup()
    {
        // A host-authored question can contain anything; unescaped markup would
        // silently mangle the printed page.
        var q = Q("p:1", "Which tag makes text <b>bold</b> & italic?", "<b>", 0);
        var html = LiveExport.QuestionPackHtml("Quiz & Co", [q]);
        Assert.Contains("&lt;b&gt;", html);
        Assert.Contains("&amp;", html);
    }
}
