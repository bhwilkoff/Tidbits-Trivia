using System;
using System.IO;
using System.Linq;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// LIVE-PACKAGE-FORMAT §7.1 — the golden package both stacks must open. The Mac
/// side runs the same assertions against the same bytes
/// (`TidbitsTriviaTests/LivePackageGoldenTests.swift`).
public class LivePackageGoldenTest : IDisposable
{
    private const string PngId = "e06f876bfc434e1656878a0db85b9a13";
    private const string WavId = "8f70a2eed10865d07de5779de0d8475e";
    private static readonly string GoldenPath =
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "live-package-golden.tidbits");
    private readonly string _scratch;

    public LivePackageGoldenTest()
    {
        _scratch = Path.Combine(Path.GetTempPath(), "tidbits-media-test-" + Guid.NewGuid().ToString("N"));
        LiveMediaStore.Directory = _scratch;
    }

    public void Dispose()
    {
        try { Directory.Delete(_scratch, recursive: true); } catch { }
    }

    private static Stream Golden() => File.OpenRead(GoldenPath);

    [Fact]
    public void Reads_the_golden_manifest_media_and_document()
    {
        using var s = Golden();
        var c = LivePackage.Read(s);
        Assert.Equal("event", c.Manifest.Kind);
        Assert.Equal("Friday Pub Quiz", c.Manifest.Title);
        Assert.Equal(new[] { WavId, PngId }, c.Manifest.Media.Select(m => m.Id).ToArray());
        var png = c.Manifest.Media[1];
        Assert.Equal("image", png.Kind);
        Assert.Equal("image/png", png.Mime);
        Assert.Equal(69, png.Bytes);
        Assert.Equal("https://example.test/golden-picture.png", png.SourceUrl);
        Assert.Equal("CC0", png.License);
        Assert.Equal(69, c.Media[PngId].Length);
        Assert.Equal(1644, c.Media[WavId].Length);
        var r0 = c.Document.Event.Rounds[0];
        Assert.Equal("tidbits-media:" + PngId, r0.Questions[0].ImageUrl);
        Assert.Equal("https://example.test/by-url.jpg", r0.Questions[1].ImageUrl);
        Assert.Equal(new string?[] { WavId, null }, r0.Audio!.ToArray());
        Assert.Null(r0.Video);
    }

    [Fact]
    public void A_foreign_zip_and_a_tampered_package_are_refused()
    {
        using var foreign = new MemoryStream();
        using (var zip = new System.IO.Compression.ZipArchive(foreign, System.IO.Compression.ZipArchiveMode.Create, true))
        {
            using var e = zip.CreateEntry("hello.txt").Open();
            e.Write("hi"u8);
        }
        foreign.Position = 0;
        Assert.Throws<LivePackage.PackageException>(() => LivePackage.Read(foreign));

        // Same entries, one media byte flipped: the hash check must fire.
        using var tampered = new MemoryStream();
        using (var src = new System.IO.Compression.ZipArchive(Golden(), System.IO.Compression.ZipArchiveMode.Read))
        using (var dst = new System.IO.Compression.ZipArchive(tampered, System.IO.Compression.ZipArchiveMode.Create, true))
        {
            foreach (var entry in src.Entries)
            {
                using var ms = new MemoryStream();
                using (var es = entry.Open()) es.CopyTo(ms);
                var bytes = ms.ToArray();
                if (entry.FullName.EndsWith(".png")) bytes[^1] ^= 0xFF;
                using var o = dst.CreateEntry(entry.FullName).Open();
                o.Write(bytes);
            }
        }
        tampered.Position = 0;
        Assert.Throws<LivePackage.PackageException>(() => LivePackage.Read(tampered));
    }

    [Fact]
    public void Import_stores_media_resolves_the_picture_and_attaches_the_clip()
    {
        using var s = Golden();
        var (ev, problems) = LivePackage.ImportIntoStore(s);
        Assert.Empty(problems);
        Assert.Equal(2, ev.Rounds.Count);
        var q0 = ev.QuestionsFor(0)[0];
        var file = LiveMediaStore.Resolve(q0.ImageUrl);
        Assert.NotNull(file);
        Assert.EndsWith(PngId + ".png", file);
        Assert.Equal(69, File.ReadAllBytes(file!).Length);
        // The joiner gets the https twin, never the store reference (§5.3).
        Assert.Equal("https://example.test/golden-picture.png", LiveMediaStore.PublishableUrl(q0.ImageUrl));
        Assert.Equal("https://example.test/by-url.jpg", LiveMediaStore.PublishableUrl(ev.QuestionsFor(0)[1].ImageUrl));
        var clip = ev.ClipFor(0, 0);
        Assert.False(string.IsNullOrEmpty(clip));
        Assert.EndsWith(WavId + ".wav", clip);
        Assert.True(File.Exists(clip));
        Assert.True(string.IsNullOrEmpty(ev.ClipFor(0, 1)));
    }

    [Fact]
    public void Pack_unpack_pack_keeps_the_manifest_media_and_the_document()
    {
        LiveEvent ev;
        using (var s = Golden()) ev = LivePackage.ImportIntoStore(s).Event;
        using var outStream = new MemoryStream();
        var dropped = LivePackage.Write(outStream, ev, "test", venue: "");
        Assert.Empty(dropped);
        outStream.Position = 0;
        var again = LivePackage.Read(outStream);
        Assert.Equal(new[] { WavId, PngId }, again.Manifest.Media.Select(m => m.Id).ToArray());
        using (var g = Golden())
            Assert.Equal(LivePackage.Read(g).Manifest.Media.Select(m => m.Sha256).ToArray(),
                         again.Manifest.Media.Select(m => m.Sha256).ToArray());
        var r0 = again.Document.Event.Rounds[0];
        Assert.Equal(ev.QuestionsFor(0).Select(q => q.Prompt).ToArray(), r0.Questions.Select(q => q.Prompt).ToArray());
        Assert.Equal("tidbits-media:" + PngId, r0.Questions[0].ImageUrl);
        Assert.Equal("https://example.test/by-url.jpg", r0.Questions[1].ImageUrl);
        Assert.Equal(new string?[] { WavId, null }, r0.Audio!.ToArray());
        Assert.Equal(0, again.Document.DroppedClipCount);
    }
}
