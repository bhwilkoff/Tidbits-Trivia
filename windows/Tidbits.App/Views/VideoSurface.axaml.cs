using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Tidbits.App.Services;

namespace Tidbits.App.Views;

/// Renders VideoFrameSink's frames (3.34). A plain Avalonia Image over a
/// WriteableBitmap — no native overlay, so it composites normally, survives the
/// projector window's chromeless full-screen, and is capturable in a headless PNG
/// (which is how the video path is verified at all).
public sealed class VideoSurface : Control
{
    private VideoFrameSink? _sink;

    public static readonly DirectProperty<VideoSurface, VideoFrameSink?> SinkProperty =
        AvaloniaProperty.RegisterDirect<VideoSurface, VideoFrameSink?>(
            nameof(Sink), o => o.Sink, (o, v) => o.Sink = v);

    public VideoFrameSink? Sink
    {
        get => _sink;
        set
        {
            if (ReferenceEquals(_sink, value)) return;
            if (_sink is not null) _sink.FrameArrived -= OnFrame;
            SetAndRaise(SinkProperty, ref _sink, value);
            if (_sink is not null) _sink.FrameArrived += OnFrame;
            InvalidateVisual();
        }
    }

    private void OnFrame() => InvalidateVisual();

    public override void Render(DrawingContext context)
    {
        var bmp = _sink?.Bitmap;
        if (bmp is null) return;

        // Aspect-FIT into the available box: a projector shows the whole frame,
        // letterboxed — never a cropped fill (the fill-image trap the Apple heads hit).
        var src = new Rect(0, 0, bmp.PixelSize.Width, bmp.PixelSize.Height);
        var box = new Rect(Bounds.Size);
        if (src.Width <= 0 || src.Height <= 0 || box.Width <= 0 || box.Height <= 0) return;

        var scale = Math.Min(box.Width / src.Width, box.Height / src.Height);
        var w = src.Width * scale;
        var h = src.Height * scale;
        var dst = new Rect((box.Width - w) / 2, (box.Height - h) / 2, w, h);
        context.DrawImage(bmp, src, dst);
    }
}
