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

        // A button with no label is a button a host cannot identify.
        var blank = buttons.Where(b => b.Content is null
                                    || (b.Content is string s && string.IsNullOrWhiteSpace(s)))
                           .ToList();
        Assert.True(blank.Count == 0, $"{blank.Count} button(s) render with no label");

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
}
