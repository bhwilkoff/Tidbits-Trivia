using System;
using System.IO;
using System.Text.Json;
using Tidbits.Core.Networking;
using Xunit;

/// Decision 060 on Windows: what a clip becomes for the phones. Windows sends a
/// web-safe file as it is (no transcoder), refuses one over the cap, and passes
/// a direct https link through — and says which, under the Play button.
public class LiveClipPublisherTest
{
    private static string Temp(string ext, int bytes)
    {
        var p = Path.Combine(Path.GetTempPath(), $"clip-{Guid.NewGuid():N}.{ext}");
        var data = new byte[bytes]; new Random(7).NextBytes(data);
        File.WriteAllBytes(p, data);
        return p;
    }

    [Fact]
    public void A_small_mp3_goes_as_bytes_with_the_exact_wire_keys()
    {
        var p = Temp("mp3", 40_000);
        var r = LiveClipPublisher.Prepare(p);
        Assert.NotNull(r.Media); Assert.NotNull(r.Node); Assert.NotNull(r.Id);
        Assert.Equal("audio", r.Media!.Kind);
        Assert.Equal("audio/mpeg", r.Media.Mime);
        Assert.Equal($"room:{r.Id}", r.Media.Url);
        Assert.Equal(40_000, r.Media.Bytes);
        Assert.StartsWith("On phones too", r.Note);
        var json = JsonSerializer.Serialize(r.Node, Wire.Json);
        Assert.Contains("\"kind\":\"audio\"", json);
        Assert.Contains("\"mime\":\"audio/mpeg\"", json);
        Assert.Contains("\"bytes\":40000", json);
        Assert.Contains("\"b64\":", json);
        var pub = new LiveRoom.Pub { Round = 1, Qid = "r0q0", Phase = LiveRoom.Phase.Question, Format = "classic", Media = r.Media with { StartedAt = 1_757_000_000_000 } };
        var pj = JsonSerializer.Serialize(pub, Wire.Json);
        Assert.Contains("\"media\":{", pj);
        Assert.Contains("\"startedAt\":1757000000000", pj);
    }

    [Fact]
    public void Over_the_cap_is_not_on_phones_and_says_so()
    {
        var p = Temp("mp3", LiveRoom.MediaMaxBytes + 1);
        var r = LiveClipPublisher.Prepare(p);
        Assert.Null(r.Media); Assert.Null(r.Node);
        Assert.Contains("Not on phones", r.Note);
    }

    [Fact]
    public void A_wav_is_not_web_safe_on_windows_and_names_the_fix()
    {
        var p = Temp("wav", 10_000);
        var r = LiveClipPublisher.Prepare(p);
        Assert.Null(r.Media);
        Assert.Contains("MP3 or M4A", r.Note);
    }

    [Fact]
    public void Links_and_room_references_parse_the_same_way_as_swift()
    {
        Assert.True(LiveClipPublisher.IsDirectFileLink("https://example.test/clip.mp3"));
        Assert.False(LiveClipPublisher.IsDirectFileLink("https://www.youtube.com/watch?v=abc"));
        Assert.Equal("abc123", LiveRoom.MediaIdFrom("room:abc123"));
        Assert.Null(LiveRoom.MediaIdFrom("room:"));
        Assert.Null(LiveRoom.MediaIdFrom("https://example.test/clip.mp3"));
        Assert.Equal("live/ABCD/media/deadbeef", LiveRoom.MediaPath("ABCD", "deadbeef"));
        Assert.Equal("m4a", LiveMediaCache.FileExtension("audio/mp4", "audio"));
        Assert.Equal("mp4", LiveMediaCache.FileExtension("", "video"));
    }
}
