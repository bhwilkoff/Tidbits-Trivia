using System;
using System.Linq;
using System.Text;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Spoiler-free result share — the byte-faithful C# twin of the web
/// `renderResults` grid + `shareResult` text (js/app.js). Kept in Core so a
/// headless test can prove parity with the web/Apple/Kotlin share string.
/// Never reveals which answer was right; the recipient still plays.
public static class ShareText
{
    public const string SiteUrl = "https://tidbitstrivia.com";

    /// The canonical twin for a single question (DEEP_LINKS.md): every platform's
    /// per-question share points here, and the WEB app renders it — so a share lands
    /// somewhere meaningful for a recipient who has never installed anything.
    public static string ItemUrl(string id) => $"{SiteUrl}/item/{Uri.EscapeDataString(id)}";

    /// One glyph per answered question: 🟢 correct · 🔴 wrong · ⚫️ timed out.
    public static string Grid(GameSummary s) =>
        string.Concat(s.Answered.Select(a =>
            a.ChosenIndex is null ? "⚫️" : a.IsCorrect ? "🟢" : "🔴"));

    /// The headline word by accuracy — mirrors web `renderResults`.
    public static string Headline(GameSummary s)
    {
        int acc = (int)Math.Round(s.Accuracy * 100);
        return acc == 100 ? "Flawless!" : acc >= 80 ? "Brilliant" : acc >= 50 ? "Nicely done" : "Good run";
    }

    /// The full shareable text. `dayStreak` is the cross-context day streak when
    /// known (0 falls back to the best-run line), matching web `shareResult`.
    public static string Compose(GameSummary s, int dayStreak = 0)
    {
        int acc = (int)Math.Round(s.Accuracy * 100);
        string header = s.DailyDay is { } day
            ? $"🧠 Tidbits Daily — {day}"
            : $"🧠 Tidbits — {s.Mode.Title()}";
        int filled = (int)Math.Round(acc * 7.0 / 100.0);
        string meter = new string('▰', filled) + new string('▱', 7 - filled);
        string streak = dayStreak >= 2 ? $"\n🔥 {dayStreak}-day streak"
            : s.MaxStreak >= 3 ? $"\n🔥 Best run {s.MaxStreak}" : "";
        var sb = new StringBuilder();
        sb.Append(header).Append('\n');
        sb.Append(s.Score).Append(" pts · ").Append(s.Correct).Append('/').Append(s.Total).Append('\n');
        sb.Append(meter).Append(' ').Append(acc).Append("%\n");
        sb.Append(Grid(s)).Append(streak).Append('\n');
        sb.Append("Play at ").Append(SiteUrl);
        return sb.ToString();
    }
}
