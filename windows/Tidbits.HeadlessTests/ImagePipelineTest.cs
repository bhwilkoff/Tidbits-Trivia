using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Headless.XUnit;
using Tidbits.App.Services;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The image pipeline decodes a bitmap, caches it, and dedupes repeat loads.
/// (Runs under AvaloniaFact so the Skia decode platform is initialized.)
public class ImagePipelineTest
{
    // A small solid-coral 8x8 RGBA PNG (Skia decodes RGBA, not the 1x1 gray+alpha).
    private const string Png1x1 =
        "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8H2P6nwEPYMInOXwUAACmjAKfi9fCtAAAAABJRU5ErkJggg==";

    [AvaloniaFact]
    public async Task Decodes_caches_and_dedupes_a_local_image()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-imgcache-{Guid.NewGuid():N}.png");
        File.WriteAllBytes(path, Convert.FromBase64String(Png1x1));
        try
        {
            Assert.Null(ImageCache.Shared.Cached(path)); // cold

            var bmp = await ImageCache.Shared.LoadAsync(path);
            Assert.NotNull(bmp);
            Assert.NotNull(ImageCache.Shared.Cached(path)); // warm

            var again = await ImageCache.Shared.LoadAsync(path);
            Assert.Same(bmp, again); // same cached instance, no re-decode
        }
        finally { File.Delete(path); }
    }

    [AvaloniaFact]
    public async Task A_bad_url_resolves_to_null_not_a_throw()
    {
        var missing = Path.Combine(Path.GetTempPath(), $"tidbits-missing-{Guid.NewGuid():N}.png");
        Assert.Null(await ImageCache.Shared.LoadAsync(missing));
    }
}
