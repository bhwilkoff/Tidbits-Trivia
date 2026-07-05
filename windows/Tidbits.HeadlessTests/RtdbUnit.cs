using System.Text;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Offline unit tests for the RTDB client's pure functions (the networked paths are
/// covered by the live smoke test, run manually / on CI with network).
public class RtdbUnit
{
    [Fact]
    public void EmailFromJwt_decodes_the_email_claim()
    {
        var payload = Convert.ToBase64String(Encoding.UTF8.GetBytes("{\"email\":\"a@b.com\",\"sub\":\"x\"}"))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        Assert.Equal("a@b.com", FirebaseRtdb.EmailFromJwt($"header.{payload}.sig"));
        Assert.Null(FirebaseRtdb.EmailFromJwt("not-a-jwt"));
    }

    [Fact]
    public void NewRoomCode_is_4_chars_from_the_shared_alphabet()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        for (int i = 0; i < 50; i++)
        {
            var code = FirebaseRtdb.NewRoomCode();
            Assert.Equal(4, code.Length);
            Assert.All(code, c => Assert.Contains(c, alphabet));
        }
    }

    [Fact]
    public void ParseEvent_reads_rtdb_sse_frames()
    {
        var put = FirebaseRtdb.ParseEvent("put", "{\"path\":\"/teams/uid1\",\"data\":{\"name\":\"Ada\"}}");
        Assert.NotNull(put);
        Assert.Equal("put", put!.Event);
        Assert.Equal("/teams/uid1", put.Path);
        Assert.Contains("Ada", put.DataJson);

        Assert.Null(FirebaseRtdb.ParseEvent("keep-alive", "null")); // keep-alives filtered

        var del = FirebaseRtdb.ParseEvent("put", "{\"path\":\"/\",\"data\":null}");
        Assert.NotNull(del);
        Assert.Null(del!.DataJson); // null data → no payload
    }
}
