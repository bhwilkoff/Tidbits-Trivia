using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Threading;

namespace Tidbits.HeadlessTests;

/// Self-tests for the visual-regression gate. A baseline harness that silently
/// passes is worse than none — these prove the comparator actually detects a
/// change, independently of any app baseline being committed yet.
public class VisualBaselineTest
{
    private static Window Swatch(Color color, int w = 80, int h = 60) =>
        new() { Width = w, Height = h, Content = new Border { Background = new SolidColorBrush(color) } };

    [AvaloniaFact]
    public void Identical_renders_report_no_differing_pixels()
    {
        var a = Swatch(Colors.CornflowerBlue);
        a.Show();
        Dispatcher.UIThread.RunJobs();
        var b = Swatch(Colors.CornflowerBlue);
        b.Show();
        Dispatcher.UIThread.RunJobs();

        var (differing, total) = VisualBaselineProbe.Diff(a.CaptureRenderedFrame()!, b.CaptureRenderedFrame()!);
        Assert.True(total > 0);
        Assert.Equal(0, differing);
    }

    [AvaloniaFact]
    public void A_changed_color_is_detected()
    {
        var a = Swatch(Colors.CornflowerBlue);
        a.Show();
        Dispatcher.UIThread.RunJobs();
        var b = Swatch(Colors.Crimson);
        b.Show();
        Dispatcher.UIThread.RunJobs();

        var (differing, total) = VisualBaselineProbe.Diff(a.CaptureRenderedFrame()!, b.CaptureRenderedFrame()!);
        // Every pixel of the swatch changed — the gate must see essentially all of them.
        Assert.True(differing > total * 0.9, $"expected a near-total diff, got {differing}/{total}");
    }

    [AvaloniaFact]
    public void A_resize_is_reported_as_fatal_not_as_a_pixel_count()
    {
        var a = Swatch(Colors.CornflowerBlue);
        a.Show();
        Dispatcher.UIThread.RunJobs();
        var b = Swatch(Colors.CornflowerBlue, w: 120);
        b.Show();
        Dispatcher.UIThread.RunJobs();

        var reason = VisualBaselineProbe.FatalReason(a.CaptureRenderedFrame()!, b.CaptureRenderedFrame()!);
        Assert.NotNull(reason);
        Assert.Contains("size changed", reason);
    }
}
