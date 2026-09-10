using System.Linq;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The wrap recap: nailed is the host's credit, once per question, a late score settles the last one.
public class LiveRecapTest
{
    private static LiveRoom.Pub P(string qid, string phase, string? answer = null, int? difficulty = null) =>
        new() { Round = 1, Qid = qid, Phase = phase, Prompt = "Q " + qid, Format = "typeAnswer", Answer = answer, Difficulty = difficulty };

    [Fact]
    public void Credit_decides_tough_and_to_remember()
    {
        var b = new LiveRecapBook();
        b.Observe(P("r0q0", LiveRoom.Phase.Question), 0);
        b.Observe(P("r0q0", LiveRoom.Phase.Reveal, "Keanu Reeves", 4), 0);
        b.Observe(P("r0q1", LiveRoom.Phase.Question), 3);
        b.Observe(P("r0q1", LiveRoom.Phase.Reveal, "Warner Bros.", 2), 3);
        b.Observe(P("end", LiveRoom.Phase.Ended), 3); b.Finish(3);
        Assert.Equal(new[] { "r0q0" }, b.Tough.Select(e => e.Qid));
        Assert.Equal(new[] { "r0q1" }, b.ToRemember.Select(e => e.Qid));
    }

    [Fact]
    public void Once_per_question_and_a_late_score_settles_the_last()
    {
        var b = new LiveRecapBook();
        b.Observe(P("r0q0", LiveRoom.Phase.Question), 0);
        b.Observe(P("r0q0", LiveRoom.Phase.Reveal, "A", 5), 0);
        b.Observe(P("r0q0", LiveRoom.Phase.Reveal, "A", 5), 0);
        b.Observe(P("end", LiveRoom.Phase.Ended), 0); b.Finish(0);
        Assert.Single(b.Entries); Assert.Empty(b.Tough);
        b.Finish(2);
        Assert.Single(b.Tough); Assert.Empty(b.ToRemember);
    }
}
