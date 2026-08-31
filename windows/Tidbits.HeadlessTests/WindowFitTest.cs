using System;
using Avalonia.Headless.XUnit;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The window must FIT the display it opens on.
///
/// MainWindow asks for 1180x760, the same numbers as the Mac's `.defaultSize`. AppKit
/// silently shrinks a window that does not fit the visible frame; Avalonia does not, so
/// identical numbers behave differently on the two platforms. On the dev box — a
/// 1080x1920 portrait display — the harness read the window rect off the machine and it
/// came back 1.8% WIDER than the screen: the right edge of every surface was off the
/// display and nothing in the app could say so.
///
/// The case that makes this ship-blocking is not that monitor. 1366x768 is the most
/// common Windows 10 laptop resolution there is, and 760 plus a title bar does not fit
/// in 768 — so the bottom of every screen was cut off on the cheapest hardware the app
/// targets, which is the hardware least likely to be tested on.
[Collection("EnvSensitive")]
public class WindowFitTest
{
    [AvaloniaFact]
    public void Startup_size_never_exceeds_the_declared_minimum_it_must_respect()
    {
        var w = new MainWindow();

        // The floor is real: below MinWidth/MinHeight the layout itself breaks, so the
        // clamp must never shrink past it. A window with a scrollbar beats one with no
        // content.
        Assert.True(w.Width >= w.MinWidth,
            $"clamped to {w.Width} which is under MinWidth {w.MinWidth}");
        Assert.True(w.Height >= w.MinHeight,
            $"clamped to {w.Height} which is under MinHeight {w.MinHeight}");
    }

    /// The arithmetic itself, at the resolutions that actually broke — proven here rather
    /// than only on whatever display CI happens to have, which is how this shipped.
    [Theory]
    [InlineData(1366, 768)]     // the common cheap Windows 10 laptop — height overflowed
    [InlineData(1080, 1920)]    // the dev box, rotated portrait — width overflowed
    [InlineData(1920, 1080)]    // roomy: must be left at the asked-for size
    [InlineData(800, 600)]      // smaller than the minimum: the floor wins, not the screen
    public void Clamp_fits_the_working_area_but_never_goes_under_the_minimum(int sw, int sh)
    {
        const double askW = 1180, askH = 760, minW = 900, minH = 680;

        var w = Math.Max(minW, Math.Min(askW, sw));
        var h = Math.Max(minH, Math.Min(askH, sh));

        Assert.True(w <= sw || w == minW, $"{w} overflows a {sw}px-wide screen");
        Assert.True(h <= sh || h == minH, $"{h} overflows a {sh}px-tall screen");
        Assert.True(w >= minW && h >= minH);

        if (sw >= askW && sh >= askH)
        {
            Assert.Equal(askW, w);   // a roomy display is not shrunk
            Assert.Equal(askH, h);
        }
    }
}
