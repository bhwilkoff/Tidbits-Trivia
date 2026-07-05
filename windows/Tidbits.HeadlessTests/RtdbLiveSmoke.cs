using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// LIVE smoke test against the real Firebase project (anon auth → put → get → delete).
/// Skipped unless TIDBITS_LIVE_SMOKE=1 (needs network + hits the live DB), so normal
/// `dotnet test` / CI stays offline-deterministic.
public class RtdbLiveSmoke
{
    [Fact]
    public async Task Anon_auth_put_get_delete_roundtrip()
    {
        if (Environment.GetEnvironmentVariable("TIDBITS_LIVE_SMOKE") != "1") return; // opt-in only

        var db = new FirebaseRtdb(tokens: new MemoryTokenStore());
        var uid = await db.EnsureAuth();
        Assert.False(string.IsNullOrEmpty(uid));

        var code = FirebaseRtdb.NewRoomCode();
        var path = $"{LiveRoom.Path("_smoke_" + code)}/meta";
        var meta = new LiveRoom.Meta { Host = uid, CreatedAt = 123, Name = "Smoke", Venue = "Test", State = "lobby" };

        await db.Put(path, meta);
        var back = await db.Get<LiveRoom.Meta>(path);
        Assert.NotNull(back);
        Assert.Equal("Smoke", back!.Name);
        Assert.Equal(uid, back.Host);

        await db.Delete(path);
        Assert.Null(await db.Get<LiveRoom.Meta>(path));
    }

    /// The WHOLE Live loop through the real backend: host opens a room + publishes an MCQ,
    /// a client joins + submits the correct answer, the host auto-scores, the client sees
    /// its score — all over live RTDB + SSE.
    [Fact]
    public async Task Host_publish_client_join_submit_score_end_to_end()
    {
        if (Environment.GetEnvironmentVariable("TIDBITS_LIVE_SMOKE") != "1") return;

        var host = new LiveHostNet(new FirebaseRtdb(tokens: new MemoryTokenStore()));
        var code = await host.Open("E2E Test");
        Assert.NotNull(code);

        var client = new LivePlayerClient(new FirebaseRtdb(tokens: new MemoryTokenStore()));
        await client.Join(code!, "Team Ada");
        Assert.True(client.Joined);

        var q = new Question { Id = "q", Prompt = "2+2?", Options = new[] { "3", "4", "5", "6" }, CorrectIndex = 1, CategoryId = "mixed" };
        var pub = new LiveRoom.Pub
        {
            Round = 1, RoundTitle = "R", Qid = "r0q0", QNum = 1, QTotal = 1,
            Phase = LiveRoom.Phase.Question, Prompt = q.Prompt, Options = q.Options, Format = "classic",
        };
        await host.Publish(pub);

        await WaitUntil(() => client.Pub?.Qid == "r0q0", 10000);
        Assert.Equal("r0q0", client.Pub?.Qid);
        await client.SubmitChoice(1); // correct

        await WaitUntil(() => host.AnswersSnapshot().Count >= 1, 10000);
        var answers = host.AnswersSnapshot();
        Assert.True(answers.Count >= 1, "host should have received the client's answer over SSE");

        // Host reveals + scores.
        await host.Publish(pub with { Phase = LiveRoom.Phase.Reveal, AnswerIndex = 1 });
        foreach (var (uid, a) in answers)
        {
            var pts = LiveScoring.Score(q, a, [], [], 1);
            if (pts > 0) await host.SetScore(uid, host.ScoreOf(uid) + pts);
        }

        await WaitUntil(() => client.Score >= 1, 10000);
        Assert.True(client.Score >= 1, "client should have seen its score over SSE");

        await client.Leave();
        await host.Close();
    }

    private static async Task WaitUntil(Func<bool> cond, int timeoutMs)
    {
        var start = Environment.TickCount64;
        while (!cond() && Environment.TickCount64 - start < timeoutMs)
            await Task.Delay(150);
    }
}
