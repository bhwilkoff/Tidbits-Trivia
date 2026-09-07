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
        try
        {
            using var src = SKBitmap.Decode(path);
            if (src is null) return null;
            int side = MaxPixels;
            int quality = 60;
            for (int i = 0; i < 5; i++)
            {
                var bytes = Jpeg(src, side, quality);
                if (bytes is null) return null;
                if (bytes.Length <= MaxBytes || side <= 320)
                    return "data:image/jpeg;base64," + Convert.ToBase64String(bytes);
                side = side * 3 / 4;
                quality = Math.Max(40, quality - 10);
            }
            return null;
        }
        catch { return null; }
    }

    private static byte[]? Jpeg(SKBitmap src, int maxSide, int quality)
    {
        var scale = Math.Min(1.0, (double)maxSide / Math.Max(src.Width, src.Height));
        var w = Math.Max(1, (int)(src.Width * scale));
        var h = Math.Max(1, (int)(src.Height * scale));
        using var surface = SKSurface.Create(new SKImageInfo(w, h, SKColorType.Rgb888x, SKAlphaType.Opaque));
        var canvas = surface.Canvas;
        canvas.Clear(SKColors.White);   // JPEG has no alpha: white behind a PNG
        using var image = SKImage.FromBitmap(src);
        canvas.DrawImage(image, new SKRect(0, 0, w, h), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.Linear));
        using var snap = surface.Snapshot();
        using var data = snap.Encode(SKEncodedImageFormat.Jpeg, quality);
        return data?.ToArray();
    }
}
