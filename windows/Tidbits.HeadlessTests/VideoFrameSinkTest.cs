using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Parity 3.34 — the video PICTURE path.
///
/// The point of the sink design: the frame pipeline takes a raw BGRA buffer, so it is
/// driven here with SYNTHETIC frames and needs no LibVLC at all. That means the video
/// path is verifiable on this arm64 Mac (which has no LibVLC native) and capturable in
/// a headless PNG — neither of which was possible with LibVLCSharp.Avalonia's
/// VideoView, the thing that was blocking 3.34.
public class VideoFrameSinkTest
{
    /// A solid-colour BGRA frame, as LibVLC's RV32 would deliver it.
    private static IntPtr Frame(int w, int h, byte b, byte g, byte r, out int stride)
    {
        stride = w * 4;
        var buf = Marshal.AllocHGlobal(stride * h);
        var bytes = new byte[stride * h];
        for (int i = 0; i < bytes.Length; i += 4)
        {
            bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = 255;
        }
        Marshal.Copy(bytes, 0, buf, bytes.Length);
        return buf;
    }

    [AvaloniaFact]
    public void Configure_allocates_a_bitmap_and_returns_the_pitch()
    {
        using var sink = new VideoFrameSink();
        var pitch = sink.Configure(64, 36);
        Assert.Equal(64 * 4, pitch);          // RV32 = 4 bytes/pixel
        Assert.NotNull(sink.Bitmap);
        Assert.Equal(64, sink.Size.Width);
        Assert.Equal(36, sink.Size.Height);
    }

    [AvaloniaFact]
    public void A_resize_reallocates_the_bitmap()
    {
        using var sink = new VideoFrameSink();
        sink.Configure(64, 36);
        var first = sink.Bitmap;
        sink.Configure(128, 72);
        Assert.NotSame(first, sink.Bitmap);
        Assert.Equal(128, sink.Size.Width);
    }

    [AvaloniaFact]
    public void The_same_size_reuses_the_bitmap()
    {
        using var sink = new VideoFrameSink();
        sink.Configure(64, 36);
        var first = sink.Bitmap;
        sink.Configure(64, 36);
        Assert.Same(first, sink.Bitmap);
    }

    [AvaloniaFact]
    public void An_invalid_size_throws_rather_than_allocating_garbage()
    {
        using var sink = new VideoFrameSink();
        Assert.Throws<ArgumentOutOfRangeException>(() => sink.Configure(0, 36));
    }

    [AvaloniaFact]
    public void A_null_frame_is_ignored()
    {
        using var sink = new VideoFrameSink();
        sink.Configure(16, 16);
        sink.WriteFrame(IntPtr.Zero, 64); // must not throw
    }

    [AvaloniaFact]
    public void A_frame_written_before_Configure_is_ignored()
    {
        using var sink = new VideoFrameSink();
        var buf = Frame(4, 4, 1, 2, 3, out var stride);
        try { sink.WriteFrame(buf, stride); } // no bitmap yet — must not throw
        finally { Marshal.FreeHGlobal(buf); }
        Assert.Null(sink.Bitmap);
    }

    [AvaloniaFact]
    public void A_written_frame_reaches_the_screen()
    {
        // The end-to-end proof: a LibVLC-shaped frame goes in, and the pixel comes out
        // of a real render. Coral (#FF5C35) so a channel-order mistake can't pass.
        using var sink = new VideoFrameSink();
        sink.Configure(32, 32);
        var buf = Frame(32, 32, b: 0x35, g: 0x5C, r: 0xFF, out var stride);
        try { sink.WriteFrame(buf, stride); }
        finally { Marshal.FreeHGlobal(buf); }
        Dispatcher.UIThread.RunJobs();

        var win = new Window { Width = 32, Height = 32, Content = new VideoSurface { Sink = sink } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var frame = win.CaptureRenderedFrame()!;
        var px = PixelAt(frame, 16, 16);
        Assert.Equal(0xFF, px.R);
        Assert.Equal(0x5C, px.G);
        Assert.Equal(0x35, px.B);
    }

    [AvaloniaFact]
    public void The_picture_is_aspect_fit_not_stretched()
    {
        // A projector must show the WHOLE frame letterboxed — never a cropped fill
        // (the fill-image trap the Apple heads hit). A 32x8 frame in a 64x64 box must
        // leave the top/bottom empty rather than stretch.
        using var sink = new VideoFrameSink();
        sink.Configure(32, 8);
        var buf = Frame(32, 8, b: 0x35, g: 0x5C, r: 0xFF, out var stride);
        try { sink.WriteFrame(buf, stride); }
        finally { Marshal.FreeHGlobal(buf); }

        var win = new Window
        {
            Width = 64,
            Height = 64,
            Background = Brushes.Black,
            Content = new VideoSurface { Sink = sink },
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var frame = win.CaptureRenderedFrame()!;
        Assert.Equal(0xFF, PixelAt(frame, 32, 32).R);   // centre = video
        var top = PixelAt(frame, 32, 2);                 // top = letterbox, not video
        Assert.True(top.R < 0x40, $"expected letterboxing at the top, got {top}");
    }

    private static Color PixelAt(Avalonia.Media.Imaging.Bitmap bmp, int x, int y)
    {
        int w = bmp.PixelSize.Width, h = bmp.PixelSize.Height, stride = w * 4, len = stride * h;
        var buf = Marshal.AllocHGlobal(len);
        try
        {
            bmp.CopyPixels(new Avalonia.PixelRect(0, 0, w, h), buf, len, stride);
            var bytes = new byte[len];
            Marshal.Copy(buf, bytes, 0, len);
            var i = y * stride + x * 4;
            // A CAPTURED frame's CopyPixels yields RGBA — note this is NOT the order a
            // PNG-decoded Bitmap gives back (that's BGRA). Same trap as the visual-gate
            // channel-order bug; CopyPixels always hands back the bitmap's native format.
            return Color.FromArgb(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
        }
        finally { Marshal.FreeHGlobal(buf); }
    }
}
