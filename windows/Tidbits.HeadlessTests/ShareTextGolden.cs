using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Proves the Windows share string is byte-faithful to the web `shareResult`
/// (js/app.js) — the spoiler-free grid + meter + streak-fallback + play link.
public class ShareTextGolden
{
    private static Question Q(string id, int correct) => new()
    {
        Id = id, Prompt = $"Prompt {id}", CategoryId = "science",
        Options = new List<string> { "A", "B", "C", "D" }, CorrectIndex = correct,
        Explanation = "Because.", Difficulty = 3,
    };

    private static AnsweredQuestion Ans(string id, int correct, int? chosen) =>
        new() { Question = Q(id, correct), ChosenIndex = chosen, SecondsTaken = 2.0 };

    [Fact]
    public void Grid_maps_correct_wrong_timeout()
    {
        var s = new GameSummary
        {
            Mode = GameMode.Classic, Category = TriviaCategory.Named("science"), Score = 240,
            Correct = 2, Total = 3, MaxStreak = 2,
            Answered = new List<AnsweredQuestion>
            {
                Ans("a", 0, 0),   // correct  -> 🟢
                Ans("b", 1, 2),   // wrong    -> 🔴
                Ans("c", 3, null),// timed out -> ⚫️
            },
        };
        Assert.Equal("🟢🔴⚫️", ShareText.Grid(s));
    }

    [Fact]
    public void Compose_matches_web_format_exactly()
    {
        var s = new GameSummary
        {
            Mode = GameMode.Classic, Category = TriviaCategory.Named("science"), Score = 240,
            Correct = 2, Total = 3, MaxStreak = 4,   // best-run fallback path (dayStreak 0)
            Answered = new List<AnsweredQuestion>
            {
                Ans("a", 0, 0), Ans("b", 1, 1), Ans("c", 3, 0),
            },
        };
        // acc = round(2/3*100) = 67 -> filled = round(67*7/100) = round(4.69) = 5
        var expected =
            "🧠 Tidbits — Classic\n" +
            "240 pts · 2/3\n" +
            "▰▰▰▰▰▱▱ 67%\n" +
            "🟢🟢🔴\n" +
            "🔥 Best run 4\n" +
            "Play at https://tidbitstrivia.com";
        Assert.Equal(expected, ShareText.Compose(s));
    }

    [Fact]
    public void Daily_header_uses_the_day_key()
    {
        var s = new GameSummary
        {
            Mode = GameMode.Daily, Category = TriviaCategory.Named("mixed"), Score = 100,
            Correct = 1, Total = 1, MaxStreak = 1, DailyDay = "2026-07-08",
            Answered = new List<AnsweredQuestion> { Ans("a", 0, 0) },
        };
        Assert.StartsWith("🧠 Tidbits Daily — 2026-07-08\n", ShareText.Compose(s));
        Assert.Contains("Play at https://tidbitstrivia.com", ShareText.Compose(s));
    }
}
