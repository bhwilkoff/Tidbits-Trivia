using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Every control on the Live surfaces, checked for the three ways a button is
/// "malformed or does not function" (owner, 2026-09-01).
///
/// The measurement that prompted this: the Live builder and cockpit carry 37
/// `Click` handlers between them and NOT ONE was named by any test. Behaviour was
/// covered — the view models and the night logic are well tested — but nothing
/// asserted that the controls a host actually presses are wired, labelled and
/// reachable. A surface nothing can drive reads as a pass (`hooks-are-coverage`).
public class LiveControlsSmokeTest
{
    private static readonly string ViewsDir =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Tidbits.App", "Views");

    private static IEnumerable<string> HandlersIn(string axaml)
    {
        var path = Path.GetFullPath(Path.Combine(ViewsDir, axaml));
        Assert.True(File.Exists(path), $"cannot find {path}");
        return Regex.Matches(File.ReadAllText(path), @"(?:Click|Checked)=""(\w+)""")
                    .Select(m => m.Groups[1].Value).Distinct();
    }

    /// Buttons the APP declared, not the ones Fluent's control templates bring with
    /// them. The first run of this flagged `PART_PageUpButton` — a RepeatButton
    /// inside the ScrollBar template — as an unlabelled button, which is true and
    /// entirely irrelevant. A check has to know what it is looking at.
    private static List<Button> AppButtons(Control view) =>
        view.GetVisualDescendants().OfType<Button>()
            .Where(b => b is not RepeatButton)
            .Where(b => b.Name is null || !b.Name.StartsWith("PART_", StringComparison.Ordinal))
            .ToList();

    /// A `Click="OnFoo"` naming a method that does not exist is a runtime blank,
    /// not a compile error, for handlers reached through a template. Reflection is
    /// the only thing that can say the wiring is real.
    [Theory]
    [InlineData("LiveView.axaml", typeof(LiveView))]
    [InlineData("LiveCockpitView.axaml", typeof(LiveCockpitView))]
    public void Every_click_handler_resolves_to_a_real_method(string axaml, Type view)
    {
        var missing = HandlersIn(axaml)
            .Where(h => view.GetMethod(h, BindingFlags.Instance | BindingFlags.Public
                                        | BindingFlags.NonPublic) is null)
            .ToList();
        Assert.True(missing.Count == 0, $"{axaml} wires handlers that do not exist: {string.Join(", ", missing)}");
    }

    [AvaloniaFact]
    public void No_button_on_the_live_builder_is_blank_or_permanently_disabled()
    {
        var view = new LiveView();
        var win = new Window { Width = 1000, Height = 800, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var buttons = AppButtons(view);
        Assert.True(buttons.Count >= 8, $"only {buttons.Count} buttons found — the view did not render");

        // A button with no label is a button a host cannot identify. An ICON button
        // (FASymbolIcon — ADVERSARIAL-DESIGN-LEDGER W3) is legitimate, but only if it
        // carries an accessible name; otherwise it is unidentifiable to a host reading
        // the screen AND to a screen reader.
        var blank = buttons.Where(b =>
        {
            // Library internals (FluentAvalonia's expander chevron) are not ours to name;
            // the expander's Header names that row on the glass.
            if (b.GetType().Namespace?.StartsWith("FluentAvalonia") == true) return false;
            if (b.Content?.GetType().Namespace?.StartsWith("FluentAvalonia") == true) return false;
            // A text label is enough on its own. ANYTHING else — an icon, a
            // ToggleSwitch whose label is the Settings row it sits in — needs an
            // accessible name. (An earlier cut of this returned "blank" for null
            // content BEFORE checking the name, which flagged two correctly-named
            // toggles: the test was wrong, not the app.)
            var text = b.Content as string;
            if (!string.IsNullOrWhiteSpace(text)) return false;
            return string.IsNullOrWhiteSpace(Avalonia.Automation.AutomationProperties.GetName(b));
        }).ToList();
        // Name them: "2 buttons are blank" cannot be acted on.
        Assert.True(blank.Count == 0,
            $"{blank.Count} button(s) with neither a text label nor an accessible name: "
            + string.Join(", ", blank.Select(b => $"{b.GetType().Name}<{b.Content?.GetType().Name ?? "null"}>")));

        // On a FRESH builder every control must be reachable. A button that is
        // disabled here can never be enabled by anything the host does on this
        // screen, which is the "does not function" complaint exactly.
        var dead = buttons.Where(b => !b.IsEnabled).Select(b => b.Content?.ToString()).ToList();
        Assert.True(dead.Count == 0, $"disabled on a fresh builder: {string.Join(", ", dead)}");
    }

    [AvaloniaFact]
    public void Every_builder_button_has_a_hit_area_a_pointer_can_reach()
    {
        // A zero-sized control is invisible to both a host and a screenshot, so it
        // passes every render check while being unusable.
        var view = new LiveView();
        var win = new Window { Width = 1000, Height = 800, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        view.ScrollToRoundsForTesting();
        Dispatcher.UIThread.RunJobs();

        var tiny = AppButtons(view)
            .Where(b => b.IsVisible && (b.Bounds.Width < 8 || b.Bounds.Height < 8))
            .Select(b => $"{b.Content} ({b.Bounds.Width:0}x{b.Bounds.Height:0})")
            .ToList();
        Assert.True(tiny.Count == 0, $"button(s) with no usable hit area: {string.Join(", ", tiny)}");
    }

    [AvaloniaFact]
    public void The_builder_reports_rather_than_silently_doing_nothing_on_an_empty_event()
    {
        // Host / Preview / Print on an event with no rounds must SAY why nothing
        // happened. Silence is indistinguishable from a broken button.
        var view = new LiveView();
        var win = new Window { Width = 1000, Height = 800, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        foreach (var name in new[] { "OnHostEvent", "OnPreviewEvent", "OnSaveEvent", "OnPrintQuestionPack" })
        {
            var status = view.GetVisualDescendants().OfType<TextBlock>()
                             .FirstOrDefault(t => t.Name == "StatusText");
            Assert.NotNull(status);
            status!.IsVisible = false;
            status.Text = "";

            typeof(LiveView).GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!
                            .Invoke(view, [view, new Avalonia.Interactivity.RoutedEventArgs()]);
            Dispatcher.UIThread.RunJobs();

            Assert.True(status.IsVisible, $"{name} on an empty event said nothing at all");
            Assert.False(string.IsNullOrWhiteSpace(status.Text), $"{name} showed an empty status");
        }
    }

    /// The brand swatch must show the colour the BIG SCREEN will paint, including
    /// when the host has typed nothing. It used to paint transparent on an empty
    /// field, which read as an empty broken box while the projector went coral
    /// (ADVERSARIAL-DESIGN-LEDGER W6).
    [AvaloniaFact]
    public void The_brand_swatch_shows_the_colour_an_unset_event_actually_uses()
    {
        var view = new LiveView();
        var win = new Window { Width = 1180, Height = 760, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var hex = view.GetVisualDescendants().OfType<TextBox>()
                      .First(t => t.Name == "BrandHexBox");
        var swatch = view.GetVisualDescendants().OfType<Border>()
                         .First(b => b.Name == "BrandSwatch");

        var fallback = Avalonia.Media.Color.Parse(
            Tidbits.App.ViewModels.LiveHostViewModel.DefaultBrandHex);

        hex.Text = "";
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(fallback,
            Assert.IsType<Avalonia.Media.SolidColorBrush>(swatch.Background).Color);

        hex.Text = "#2D5BFF";
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(Avalonia.Media.Color.Parse("#2D5BFF"),
            Assert.IsType<Avalonia.Media.SolidColorBrush>(swatch.Background).Color);

        // Garbage falls back rather than painting nothing.
        hex.Text = "#zzz";
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(fallback,
            Assert.IsType<Avalonia.Media.SolidColorBrush>(swatch.Background).Color);
    }
}
