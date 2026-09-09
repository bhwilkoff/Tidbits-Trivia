using System;
using System.IO;
using System.Text.Json;
using Tidbits.Core.Networking;
using Xunit;

/// Decision 060 (pictures) on Windows: a photo-sized store picture splits into a
/// ≤120 KB room node and a ≤20 KB fallback; a small one stays a data URL alone.
/// The JPEG maker is stubbed: SkiaSharp's natives are not loadable on the Mac
/// head's test process, and the SPLIT rules are what this pins — the real
/// encoder is exercised by the projector/cockpit snapshots on windows-latest.
public class LivePictureNodeTest
{
    private static byte[] Bytes(int n, byte seed) { var b = new byte[n]; for (int i = 0; i < n; i++) b[i] = (byte)(seed + i); return b; }

    private static string StoreOne(byte seed)
    {
        var dir = Path.Combine(Path.GetTempPath(), $"picnode-{Guid.NewGuid():N}");
        Directory.CreateDirectory(dir);
        LiveMediaStore.Directory = dir;
        return LiveMediaStore.Store(Bytes(5000, seed), "png", "photo.png");
    }

    [Fact]
    public void A_big_picture_becomes_a_node_plus_a_small_fallback()
    {
        var prevDir = LiveMediaStore.Directory; var prevProv = LiveMediaStore.JpegProvider;
        try
        {
            LiveMediaStore.JpegProvider = (path, side, max) => side >= 800 ? Bytes(90_000, 1) : Bytes(15_000, 2);
            var id = StoreOne(11);
            var pic = LiveMediaStore.PublishPicture(LiveMediaStore.Reference(id));
            Assert.NotNull(pic.Node); Assert.NotNull(pic.Wire); Assert.NotNull(pic.Id);
            Assert.Equal("image", pic.Node!.Kind); Assert.Equal("image/jpeg", pic.Node.Mime); Assert.Equal(90_000, pic.Node.Bytes);
            Assert.Equal($"room:{pic.Id}", pic.Wire!.Url); Assert.Equal(32, pic.Id!.Length); Assert.Equal("photo", pic.Wire.Name);
            Assert.StartsWith("data:image/jpeg;base64,", pic.Fallback);
            Assert.True(pic.Fallback!.Length <= LiveMediaStore.FallbackMaxBytes * 4 / 3 + 64, $"fallback {pic.Fallback.Length} chars");
            var pub = new LiveRoom.Pub { Round = 1, Qid = "r0q0", Phase = LiveRoom.Phase.Question, Format = "pictureId", ImageUrl = pic.Fallback, Picture = pic.Wire };
            var json = JsonSerializer.Serialize(pub, Wire.Json);
            Assert.Contains("\"picture\":{", json); Assert.Contains("\"kind\":\"image\"", json);
            Assert.Equal("jpg", LiveMediaCache.FileExtension("image/jpeg", "image"));
        }
        finally { LiveMediaStore.Directory = prevDir; LiveMediaStore.JpegProvider = prevProv; }
    }

    [Fact]
    public void A_small_picture_stays_a_data_url_with_no_node()
    {
        var prevDir = LiveMediaStore.Directory; var prevProv = LiveMediaStore.JpegProvider;
        try
        {
            LiveMediaStore.JpegProvider = (path, side, max) => Bytes(12_000, 3);
            var id = StoreOne(12);
            var pic = LiveMediaStore.PublishPicture(LiveMediaStore.Reference(id));
            Assert.Null(pic.Node); Assert.Null(pic.Wire);
            Assert.StartsWith("data:image/jpeg;base64,", pic.Fallback);
        }
        finally { LiveMediaStore.Directory = prevDir; LiveMediaStore.JpegProvider = prevProv; }
    }

    [Fact]
    public void An_https_twin_passes_through_untouched()
    {
        Assert.Equal("https://example.test/a.jpg", LiveMediaStore.PublishPicture("https://example.test/a.jpg").Fallback);
        Assert.Null(LiveMediaStore.PublishPicture("https://example.test/a.jpg").Node);
    }
}
