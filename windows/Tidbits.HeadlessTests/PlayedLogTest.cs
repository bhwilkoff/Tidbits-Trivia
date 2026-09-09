using System;
using System.IO;
using System.Linq;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// 3.56 — a re-run night must be able to name what the room already heard.
public class PlayedLogTest
{
    private static string TempPath() => Path.Combine(Path.GetTempPath(), "tidbits-played-" + Guid.NewGuid().ToString("N") + ".json");

    [Fact]
    public void A_hosted_question_is_remembered_and_survives_a_reload()
    {
        var path = TempPath();
        try
        {
            var t1 = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
            var t2 = DateTimeOffset.FromUnixTimeSeconds(2_000_000);
            var log = new PlayedLog(path);
            log.Record(new[] { "q1", "q2", "" }, "Friday Pub Quiz", t1);
            log.Record(new[] { "q2" }, "Tuesday Special", t2);
            var again = new PlayedLog(path);
            Assert.Equal(new[] { "q1", "q2" }, again.Ids.OrderBy(x => x));
            Assert.Equal("Friday Pub Quiz", again.Entry("q1")!.Night);
            Assert.Equal(t2, again.Entry("q2")!.At);
            Assert.Null(again.Entry("q3"));
            again.Clear();
            Assert.Empty(new PlayedLog(path).Ids);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void The_badge_reads_like_a_person()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        string Line(double daysAgo, string night = "Pub Quiz") =>
            PlayedLog.AskedLine(new PlayedEntry { At = now.AddDays(-daysAgo), Night = night }, now);
        Assert.Equal("Asked today · Pub Quiz", Line(0));
        Assert.Equal("Asked yesterday · Pub Quiz", Line(1));
        Assert.Equal("Asked 6 days ago · Pub Quiz", Line(6));
        Assert.Equal("Asked 3 weeks ago · Pub Quiz", Line(21));
        Assert.StartsWith("Asked ", Line(90)); Assert.DoesNotContain("ago", Line(90));
        Assert.Equal("Asked 2 days ago", Line(2, "  "));
    }
}
