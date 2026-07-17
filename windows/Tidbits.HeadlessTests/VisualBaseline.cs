using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;

namespace Tidbits.HeadlessTests;

/// Visual-regression gate (WINDOWS-PLAYBOOK §4). Snapshots were being captured but
/// never COMPARED — a regression only surfaced if a human happened to look at the
/// artifact. This diffs each render against a committed baseline so the CI run fails
/// on an unintended visual change.
///
/// Baselines are captured on WINDOWS, the ship target, and only enforced there:
/// Skia's rasterization and font fallback are not guaranteed identical between the
/// macOS dev head and Windows, so a Mac-captured baseline would fail on CI for
/// reasons that have nothing to do with the app. On non-Windows the comparison is
/// skipped (the render still runs, so a crash/layout exception is still caught).
///
/// Refresh baselines with TIDBITS_UPDATE_BASELINES=1 — run it on windows-latest via
/// the `windows-repl.yml` workflow, then download and commit the artifact.
public static class VisualBaseline
{
    private const double DefaultTolerance = 0.001; // 0.1% of pixels may differ

    private static string BaselineDir()
    {
        // Walk up from the test binary to the project dir so baselines live in the repo,
        // not in bin/.
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d is not null && !File.Exists(Path.Combine(d.FullName, "Tidbits.HeadlessTests.csproj")))
            d = d.Parent;
        var root = d?.FullName ?? AppContext.BaseDirectory;
        return Path.Combine(root, "Baselines", "windows");
    }

    private static string ArtifactDir()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static bool Enforced =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
        && Environment.GetEnvironmentVariable("TIDBITS_UPDATE_BASELINES") != "1";

    private static bool Updating =>
        Environment.GetEnvironmentVariable("TIDBITS_UPDATE_BASELINES") == "1";

    /// Capture `win`, always write the artifact PNG, and — on Windows — assert it
    /// matches the committed baseline within `tolerance` (fraction of differing pixels).
    public static void Matches(Window win, string name, double tolerance = DefaultTolerance)
    {
        Dispatcher.UIThread.RunJobs();
        var frame = win.CaptureRenderedFrame()
                    ?? throw new InvalidOperationException($"'{name}' captured no frame — is the window shown?");

        var artifact = Path.Combine(ArtifactDir(), $"{name}.png");
        frame.Save(artifact);

        var baselineDir = BaselineDir();
        var baselinePath = Path.Combine(baselineDir, $"{name}.png");

        if (Updating)
        {
            Directory.CreateDirectory(baselineDir);
            frame.Save(baselinePath);
            return;
        }

        if (!Enforced) return; // macOS dev head: render-only, no pixel gate

        Assert.True(File.Exists(baselinePath),
            $"No baseline for '{name}'. Run the windows-repl workflow with " +
            $"TIDBITS_UPDATE_BASELINES=1, then commit Baselines/windows/{name}.png.");

        using var expected = new Bitmap(baselinePath);
        var (differing, total, reason) = Compare(expected, frame);

        if (reason is not null)
        {
            frame.Save(Path.Combine(ArtifactDir(), $"{name}-actual.png"));
            Assert.Fail($"'{name}' does not match its baseline: {reason}. " +
                        $"See {name}-actual.png in the artifacts.");
        }

        var fraction = total == 0 ? 0 : (double)differing / total;
        if (fraction > tolerance)
        {
            frame.Save(Path.Combine(ArtifactDir(), $"{name}-actual.png"));
            Assert.Fail(
                $"'{name}' drifted from its baseline: {fraction:P3} of pixels differ " +
                $"({differing}/{total}), tolerance {tolerance:P3}. " +
                $"Compare {name}.png (baseline) with {name}-actual.png in the artifacts. " +
                $"If the change is intended, refresh the baseline with TIDBITS_UPDATE_BASELINES=1.");
        }
    }

    /// Per-pixel compare. Returns (differingPixels, totalPixels, fatalReason).
    internal static (int, int, string?) Compare(Bitmap expected, Bitmap actual)
    {
        var es = expected.PixelSize;
        var a2 = actual.PixelSize;
        if (es != a2)
            return (0, 0, $"size changed {es.Width}x{es.Height} -> {a2.Width}x{a2.Height}");

        int w = es.Width, h = es.Height, stride = w * 4, len = stride * h;
        var eBuf = Marshal.AllocHGlobal(len);
        var aBuf = Marshal.AllocHGlobal(len);
        try
        {
            expected.CopyPixels(new PixelRect(0, 0, w, h), eBuf, len, stride);
            actual.CopyPixels(new PixelRect(0, 0, w, h), aBuf, len, stride);

            var e = new byte[len];
            var a = new byte[len];
            Marshal.Copy(eBuf, e, 0, len);
            Marshal.Copy(aBuf, a, 0, len);

            int differing = 0;
            for (int i = 0; i < len; i += 4)
            {
                // Tolerate 1-level channel noise from rasterization; count anything above it.
                if (Math.Abs(e[i] - a[i]) > 1 || Math.Abs(e[i + 1] - a[i + 1]) > 1 ||
                    Math.Abs(e[i + 2] - a[i + 2]) > 1 || Math.Abs(e[i + 3] - a[i + 3]) > 1)
                    differing++;
            }
            return (differing, w * h, null);
        }
        finally
        {
            Marshal.FreeHGlobal(eBuf);
            Marshal.FreeHGlobal(aBuf);
        }
    }
}

/// Test seam onto VisualBaseline's comparator, so the gate itself is provably able
/// to detect a change (VisualBaselineTest) without needing committed baselines.
internal static class VisualBaselineProbe
{
    public static (int Differing, int Total) Diff(Bitmap a, Bitmap b)
    {
        var (d, t, _) = VisualBaseline.Compare(a, b);
        return (d, t);
    }

    public static string? FatalReason(Bitmap a, Bitmap b) => VisualBaseline.Compare(a, b).Item3;
}
