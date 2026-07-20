using System.Diagnostics;
using System.Net;
using System.Text;

namespace Tidbits.Core.Networking;

/// Opens the user's browser. The ONLY UI-ish edge in the sign-in flow, isolated so the
/// rest is unit-testable on the Mac head (per the Windows playbook: behaviour is a pure
/// function, the platform call is a thin guarded edge).
public interface IBrowserLauncher
{
    void Open(string url);
}

public sealed class SystemBrowserLauncher : IBrowserLauncher
{
    public void Open(string url) =>
        Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
}

/// Records the URL instead of opening it — lets the full flow run in tests.
public sealed class FakeBrowserLauncher : IBrowserLauncher
{
    public string? LastUrl { get; private set; }
    public void Open(string url) => LastUrl = url;
}

/// Binds an ephemeral loopback port and waits for the single OAuth redirect.
///
/// Loopback (127.0.0.1) rather than a custom URI scheme because it works in an
/// unpackaged build too — the MSIX `windows.protocol` handler only exists in the Store
/// package, and sign-in has to work in the direct-download .exe as well.
public sealed class LoopbackAuthListener : IDisposable
{
    private readonly HttpListener _listener = new();

    public string RedirectUri { get; }

    /// The bound port. Apple's flow needs this at runtime: Apple allows only ONE
    /// pre-registered redirect URI, so the bounce Worker learns the ephemeral port from
    /// `state` (docs/APPLE-SIGNIN-WINDOWS.md).
    public int Port { get; }

    public LoopbackAuthListener(int? fixedPort = null)
    {
        Port = fixedPort ?? FreePort();
        RedirectUri = $"http://127.0.0.1:{Port}/";
        _listener.Prefixes.Add(RedirectUri);
        _listener.Start();
    }

    /// Wait for the browser redirect, serve a closing page, and return the RAW query so the
    /// caller can parse it with its own provider's contract (Google returns `code`, Apple
    /// returns `id_token`). `looksSuccessful` only picks which closing page to show.
    public async Task<string> WaitForRawQuery(CancellationToken ct = default)
    {
        using var reg = ct.Register(() => { try { _listener.Stop(); } catch { } });
        var ctx = await _listener.GetContextAsync();
        var query = ctx.Request.Url?.Query ?? "";

        var ok = query.Contains("code=") || query.Contains("id_token=");
        var html = Encoding.UTF8.GetBytes(GoogleOAuth.SuccessPageHtml(ok));
        ctx.Response.ContentType = "text/html; charset=utf-8";
        ctx.Response.ContentLength64 = html.Length;
        await ctx.Response.OutputStream.WriteAsync(html, ct);
        ctx.Response.Close();
        return query;
    }

    /// Google-shaped convenience wrapper.
    public async Task<GoogleOAuth.Callback> WaitForCallback(CancellationToken ct = default) =>
        GoogleOAuth.ParseCallback(await WaitForRawQuery(ct));

    private static int FreePort()
    {
        var l = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    public void Dispose()
    {
        try { if (_listener.IsListening) _listener.Stop(); } catch { }
        ((IDisposable)_listener).Dispose();
    }
}
