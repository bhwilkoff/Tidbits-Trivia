using System;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace Tidbits.App.Services;

/// The video picture path (parity 3.34).
///
/// Why not LibVLCSharp.Avalonia's VideoView: it is compiled against Avalonia 11 and
/// throws MissingMethodException (Visual.get_VisualRoot) at runtime under Avalonia 12.
/// This takes LibVLC's raw RV32 frames and writes them into a WriteableBitmap
/// instead — which is version-INDEPENDENT (no Avalonia dependency inside LibVLC's
/// path at all) and, unlike a native overlay, headless-verifiable: a frame that lands
/// here can be captured in a PNG.
///
/// The sink is deliberately ignorant of LibVLC: it accepts a pointer to a buffer of
/// BGRA bytes. That is what lets the whole pipeline be tested with synthetic frames
/// on any OS, leaving only the callback wiring to be proven on Windows CI (where a
/// real LibVLC exists — arm64 macOS has no LibVLC native).
public sealed class VideoFrameSink : IDisposable
{
    private readonly object _gate = new();
    private WriteableBitmap? _bitmap;
    private bool _disposed;

    public PixelSize Size { get; private set; }

    /// Raised on the UI thread after a frame lands, so a view can invalidate.
    public event Action? FrameArrived;

    /// The bitmap the view binds to. Null until the first Configure.
    public WriteableBitmap? Bitmap { get { lock (_gate) return _bitmap; } }

    /// LibVLC calls this (via AvPlayer) once it knows the video dimensions.
    /// Returns the pitch (bytes per row) LibVLC must use — RV32 is 4 bytes/pixel.
    public int Configure(int width, int height)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentOutOfRangeException(nameof(width), $"invalid video size {width}x{height}");

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_bitmap is null || Size.Width != width || Size.Height != height)
            {
                _bitmap?.Dispose();
                // Bgra8888 matches LibVLC's "RV32" on little-endian, so frames copy
                // straight in with no per-pixel conversion.
                _bitmap = new WriteableBitmap(
                    new PixelSize(width, height), new Vector(96, 96),
                    PixelFormat.Bgra8888, AlphaFormat.Opaque);
                Size = new PixelSize(width, height);
            }
            return width * 4;
        }
    }

    /// Copy one frame in. `source` points at width*height*4 BGRA bytes.
    /// Safe to call from LibVLC's decoder thread — the copy is locked and the UI-thread
    /// notification is marshalled.
    public unsafe void WriteFrame(IntPtr source, int sourceStride)
    {
        if (source == IntPtr.Zero) return;

        lock (_gate)
        {
            if (_disposed || _bitmap is null) return;

            using var fb = _bitmap.Lock();
            var dstStride = fb.RowBytes;
            var rowBytes = Math.Min(sourceStride, dstStride);
            var src = (byte*)source;
            var dst = (byte*)fb.Address;

            for (int y = 0; y < Size.Height; y++)
                Buffer.MemoryCopy(src + (long)y * sourceStride, dst + (long)y * dstStride,
                                  dstStride, rowBytes);
        }

        // Never raise under the lock: a handler that touches Bitmap would deadlock
        // against the next frame.
        Dispatcher.UIThread.Post(() => FrameArrived?.Invoke(), DispatcherPriority.Render);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _bitmap?.Dispose();
            _bitmap = null;
        }
    }
}
