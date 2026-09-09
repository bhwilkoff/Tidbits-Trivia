using System;
using System.IO;
using SkiaSharp;

namespace Tidbits.App.Services;

/// The Windows twin of the Mac's `LiveMediaStore.dataURL`: a store picture →
/// `data:image/jpeg;base64,…`, the longest side ≤ 800px, JPEG 60, shrinking
/// until it is under ~120 KB so the whole room can fetch it on venue Wi-Fi
/// (LIVE-PACKAGE-FORMAT §5.3). Installed into Core's `LiveMediaStore` at startup
/// because Core has no image codec.
public static class MediaPublisher
{
    public const int MaxPixels = 800;
    public const int MaxBytes = 120_000;

    public static string? DataUrl(string path)
    {
        var bytes = JpegUnder(path, MaxPixels, MaxBytes);
        return bytes is null ? null : "data:image/jpeg;base64," + Convert.ToBase64String(bytes);
    }

    /// A JPEG no larger than `maxSide` and, by shrinking, no heavier than
    /// `maxBytes` (floor: 160 px). The Decision 060 picture node and its small
    /// fallback are both made here.
    public static byte[]? JpegUnder(string path, int maxSide, int maxBytes)
    {
        try
        {
            LaunchHooks.Diag($"JpegUnder: {path} exists={File.Exists(path)} side={maxSide} max={maxBytes}");
            using var src = SKBitmap.Decode(path);
            if (src is null) { LaunchHooks.Diag("JpegUnder: decode returned null"); return null; }
            int side = maxSide;
            int quality = 60;
            for (int i = 0; i < 6; i++)
            {
                var bytes = Jpeg(src, side, quality);
                if (bytes is null) { LaunchHooks.Diag("JpegUnder: encode returned null"); return null; }
                if (bytes.Length <= maxBytes || side <= 160) { LaunchHooks.Diag($"JpegUnder: ok {bytes.Length} bytes at {side}px"); return bytes; }
                side = side * 3 / 4;
                quality = Math.Max(40, quality - 10);
            }
            return null;
        }
        catch (Exception ex) { LaunchHooks.Diag($"JpegUnder: FAILED {ex}"); return null; }
    }

    private static byte[]? Jpeg(SKBitmap src, int maxSide, int quality)
    {
        var scale = Math.Min(1.0, (double)maxSide / Math.Max(src.Width, src.Height));
        var w = Math.Max(1, (int)(src.Width * scale));
        var h = Math.Max(1, (int)(src.Height * scale));
        // The platform's default 8888 format, NOT Rgb888x: Skia's JPEG encoder
        // returned null for an Rgb888x raster on the real Windows box, so every
        // store-only picture silently had no data URL and no node (2026-09-09).
        using var surface = SKSurface.Create(new SKImageInfo(w, h));
        var canvas = surface.Canvas;
        canvas.Clear(SKColors.White);   // JPEG has no alpha: white behind a PNG
        using var image = SKImage.FromBitmap(src);
        canvas.DrawImage(image, new SKRect(0, 0, w, h), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.Linear));
        using var snap = surface.Snapshot();
        using var data = snap.Encode(SKEncodedImageFormat.Jpeg, quality);
        return data?.ToArray();
    }
}
