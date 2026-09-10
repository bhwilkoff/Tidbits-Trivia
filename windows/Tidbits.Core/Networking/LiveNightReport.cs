using System;
using System.Collections.Generic;
using System.Linq;

namespace Tidbits.Core.Networking;

/// The night, read back (A3.11 / 3.68): which questions the room found hard
/// and easy, how each round went, how many tables were answering — from the
/// answer sheet the host already keeps; no backend, as private as the sheet.
/// A poll is not a question anyone got wrong, so polls are left out.
/// Mirrors Swift LiveNightReport.
public sealed class LiveNightReport
{
    public sealed record QuestionStat(string Qid, int Round, int Number, string Prompt, string Answer, int Answered, int Credited)
    {
        public double Accuracy => Answered == 0 ? 0 : (double)Credited / Answered;
    }
    public sealed record RoundStat(int Round, int Questions, int Answered, int Credited)
    {
        public double Accuracy => Answered == 0 ? 0 : (double)Credited / Answered;
    }

    public IReadOnlyList<QuestionStat> Questions { get; }
    public IReadOnlyList<RoundStat> Rounds { get; }
    public int Teams { get; }

    private LiveNightReport(IReadOnlyList<QuestionStat> q, IReadOnlyList<RoundStat> r, int teams) { Questions = q; Rounds = r; Teams = teams; }

    public bool IsEmpty => Questions.Count == 0;
    /// The question the fewest answering tables got (ties: the one more tables missed).
    public QuestionStat? Hardest => Questions.Where(q => q.Answered > 0)
        .OrderBy(q => q.Accuracy).ThenByDescending(q => q.Answered - q.Credited).FirstOrDefault();
    public QuestionStat? Easiest => Questions.Where(q => q.Answered > 0)
        .OrderByDescending(q => q.Accuracy).ThenByDescending(q => q.Credited).FirstOrDefault();
    /// Answers per question, as a share of the tables in the room (0…1).
    public double Participation => Teams > 0 && Questions.Count > 0
        ? Math.Min(1, Questions.Average(q => q.Answered) / Teams) : 0;
    public double OverallAccuracy
    {
        get { var a = Questions.Sum(q => q.Answered); return a == 0 ? 0 : (double)Questions.Sum(q => q.Credited) / a; }
    }

    public static LiveNightReport From(IReadOnlyList<LiveAnswerRecord> log, int teams)
    {
        var qs = log.Where(r => r.Answer != "(poll)")
            .Select(r => new QuestionStat(r.Qid, r.Round, r.Number, r.Prompt, r.Answer, r.Lines.Count, r.Lines.Count(l => l.Points > 0)))
            .ToList();
        var rounds = qs.GroupBy(q => q.Round).OrderBy(g => g.Key)
            .Select(g => new RoundStat(g.Key, g.Count(), g.Sum(q => q.Answered), g.Sum(q => q.Credited))).ToList();
        return new LiveNightReport(qs, rounds, teams);
    }

    public static string Percent(double x) => $"{(int)Math.Round(x * 100)}%";
}
