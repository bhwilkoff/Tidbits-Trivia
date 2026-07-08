using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;

namespace Tidbits.App.Services;

/// Decoded-bitmap cache over a single capped HttpClient — the Windows twin of the
/// macOS ImagePipeline. Dedupes concurrent requests per URL and bounds the cache.
/// Avalonia's Bitmap decodes to a display-ready surface (no grayscale-white-box
/// trap the Metal path had on macOS), so no manual sRGB conversion is needed.
public sealed class ImageCache
{
    public static readonly ImageCache Shared = new();

    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private readonly ConcurrentDictionary<string, Task<Bitmap?>> _inflight = new();
    private readonly ConcurrentDictionary<string, Bitmap> _cache = new();
    private const int Cap = 64;

    /// Already-decoded bitmap for this URL, or null (so callers can render
    /// synchronously on a cache hit and only go async on a miss).
    public Bitmap? Cached(string url) => _cache.TryGetValue(url, out var b) ? b : null;

    /// Decode (or return cached). Concurrent calls for the same URL share one
    /// fetch. Returns null on any failure — callers show a fallback.
    public Task<Bitmap?> LoadAsync(string url)
    {
        if (_cache.TryGetValue(url, out var hit)) return Task.FromResult<Bitmap?>(hit);
        return _inflight.GetOrAdd(url, DecodeAsync);
    }

    private async Task<Bitmap?> DecodeAsync(string url)
    {
        try
        {
            Stream stream;
            if (url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                stream = new MemoryStream(await _http.GetByteArrayAsync(url));
            else
                stream = File.OpenRead(url);
            using (stream)
            {
                var bmp = new Bitmap(stream);
                _cache[url] = bmp;
                if (_cache.Count > Cap) TrimOne();
                return bmp;
            }
        }
        catch
        {
            return null;
        }
        finally
        {
            _inflight.TryRemove(url, out _);
        }
    }

    private void TrimOne()
    {
        foreach (var key in _cache.Keys) { _cache.TryRemove(key, out _); break; }
    }
}
