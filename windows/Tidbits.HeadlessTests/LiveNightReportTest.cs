using System.Linq;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// 3.68 — the night read back from the answer sheet. Mirrors the Swift suite.
public class LiveNightReportTest
{
    private static LiveAnswerRecord Rec(string qid, int round, int n, int[] points, string answer = "A") =>
        new(qid, round, n, "Q " + qid, answer, points.Select((p, i) => new LiveAnswerRecord.Line("u" + i, "T" + i, "x", p)).ToList());

    [Fact]
    public void Hardest_easiest_rounds_and_participation_come_from_the_sheet()
    {
        var log = new[]
        {
            Rec("r0q0", 1, 1, new[] { 1, 1, 0, 0 }),
            Rec("r0q1", 1, 2, new[] { 1, 1, 1, 0 }),
            Rec("r1q2", 2, 1, new[] { 0, 0, 0 }),
            Rec("r1q3", 2, 2, new[] { 0, 0, 0, 0 }, "(poll)"),
        };
        var r = LiveNightReport.From(log, 4);
        Assert.Equal(3, r.Questions.Count);
        Assert.Equal("r1q2", r.Hardest!.Qid);
        Assert.Equal("r0q1", r.Easiest!.Qid);
        Assert.Equal(new[] { 1, 2 }, r.Rounds.Select(x => x.Round));
        Assert.Equal("63%", LiveNightReport.Percent(r.Rounds[0].Accuracy));
        Assert.Equal(0, r.Rounds[1].Accuracy);
        Assert.InRange(r.Participation - (11.0 / 3.0) / 4.0, -0.001, 0.001);
        Assert.Equal("45%", LiveNightReport.Percent(r.OverallAccuracy));
    }

    [Fact]
    public void Empty_sheet_and_unanswered_questions()
    {
        Assert.True(LiveNightReport.From(System.Array.Empty<LiveAnswerRecord>(), 3).IsEmpty);
        var r = LiveNightReport.From(new[] { Rec("r0q0", 1, 1, System.Array.Empty<int>()), Rec("r0q1", 1, 2, new[] { 1 }) }, 1);
        Assert.Equal("r0q1", r.Hardest!.Qid); Assert.Equal("r0q1", r.Easiest!.Qid);
        Assert.Equal(0.5, r.Participation);
    }
}
