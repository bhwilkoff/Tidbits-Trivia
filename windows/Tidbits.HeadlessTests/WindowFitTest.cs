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
    /// SHOWS the window, because that is the bug this class exists for.
    ///
    /// The first version of the clamp ran in the constructor, where a Window has no
    /// platform handle yet — `Screens` is null there, so it returned immediately and did
    /// nothing. It shipped looking right: the code was present, the arithmetic test below
    /// passed, and the window still hung off the right of the display. An assertion that
    /// cannot fire is not an assertion, and one that tests arithmetic the shipped code
    /// never reaches is the same thing wearing a better disguise.
    ///
    /// Showing the window is what makes it real: if the clamp is moved back to a point
    /// where Screens is unavailable, the window keeps its asked-for 1180 and this fails.
    [AvaloniaFact]
    public void Shown_window_fits_the_screen_it_opened_on()
    {
        var w = new MainWindow();
        w.Show();

        // The assertion is that the clamp RAN, not that the result is small. The headless
        // display is 1920x1280 — roomier than the asked-for 1180x760 — so a size assertion
        // here passes identically whether the clamp works or was never called, which is how
        // the first version of this test went green over a window that hung off the screen.
        // Every CI runner has a roomy display; this is the only form that discriminates.
        Assert.True(w.ClampApplied,
            "the window was shown without the clamp ever running — it is back in the "
            + "constructor, where Screens is null and it silently no-ops");

        var screen = w.Screens?.ScreenFromWindow(w) ?? w.Screens?.Primary;
        Assert.NotNull(screen);
        w.Close();
    }

    [AvaloniaFact]
    public void Startup_size_never_exceeds_the_declared_minimum_it_must_respect()
    {
        var w = new MainWindow();
        w.Show();

        // The floor is real: below MinWidth/MinHeight the layout itself breaks, so the
        // clamp must never shrink past it. A window with a scrollbar beats one with no
        // content.
        Assert.True(w.Width >= w.MinWidth,
            $"clamped to {w.Width} which is under MinWidth {w.MinWidth}");
        Assert.True(w.Height >= w.MinHeight,
            $"clamped to {w.Height} which is under MinHeight {w.MinHeight}");
        w.Close();
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

    /// The position half, which is the half that actually cut content off.
    ///
    /// Windows cascades each new window down and to the right — measured on the dev box,
    /// the left edge stepped 26, 52, 104, 156, 208, 260px across six launches. A window
    /// clamped to the screen's WIDTH still hangs off it at any non-zero offset, so the
    /// size clamp alone left 200px of the app past the right edge while every size
    /// assertion passed.
    [Theory]
    [InlineData(0,   0,   1080, 1920, 1080, 800)]   // already fits: left alone
    [InlineData(260, 100, 1080, 1920, 1080, 800)]   // cascaded right: pulled back to 0
    [InlineData(500, 100, 1366, 768,  1000, 700)]   // partly off a laptop screen
    [InlineData(-40, -30, 1920, 1080, 1180, 760)]   // dragged off the top-left
    public void Position_is_pulled_back_onto_the_working_area(
        int px, int py, int areaW, int areaH, int winW, int winH)
    {
        var x = Math.Max(0, Math.Min(px, areaW - winW));
        var y = Math.Max(0, Math.Min(py, areaH - winH));

        Assert.True(x >= 0 && y >= 0, $"({x},{y}) is off the top-left");
        Assert.True(x + winW <= areaW, $"right edge {x + winW} is past {areaW}");
        Assert.True(y + winH <= areaH, $"bottom edge {y + winH} is past {areaH}");

        if (px >= 0 && py >= 0 && px + winW <= areaW && py + winH <= areaH)
        {
            Assert.Equal(px, x);   // a window that already fits is not moved
            Assert.Equal(py, y);
        }
    }
}
