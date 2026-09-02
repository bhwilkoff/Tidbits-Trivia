using System.Collections.Generic;
using System.Linq;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The per-round control strip in the Live builder.
///
/// These exist because a SNAPSHOT test did not catch the bug they cover: the Buzz
/// toggle and the countdown ComboBox were both assigned Grid column 2, so Avalonia
/// stacked them in one cell and the toggle drew ON TOP of the dropdown. The
/// rendered PNG still looked like a plausible builder, and its baseline was
/// captured with the defect already in it, so every run was green.
///
/// A picture cannot assert "these two controls do not occupy the same cell". The
/// layout can.
public class LiveBuilderLayoutTest
{
    private static LiveView Builder(int rounds = 2)
    {
        var view = new LiveView();
        var win = new Window { Width = 900, Height = 700, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        var rl = new List<NightRound>();
        for (int i = 0; i < rounds; i++) rl.Add(new NightRound { Kind = GameMode.Classic, Count = 4 });
        view.LoadEventForTesting(new LiveEvent { Name = "Layout", Rounds = rl });
        Dispatcher.UIThread.RunJobs();
        return view;
    }

    /// The Grid that holds round `n`'s controls, found by one of its named buttons.
    private static Grid RowFor(LiveView view, int n) =>
        view.GetVisualDescendants().OfType<Grid>()
            .First(g => g.Children.Any(c => AutomationProperties.GetName(c) == $"Move round {n} up"));

    [AvaloniaFact]
    public void No_two_controls_in_a_round_row_share_a_grid_column()
    {
        var row = RowFor(Builder(), 1);
        var used = row.Children.Select(Grid.GetColumn).ToList();
        Assert.Equal(used.Count, used.Distinct().Count());
    }

    [AvaloniaFact]
    public void Every_round_control_fits_inside_the_declared_columns()
    {
        var row = RowFor(Builder(), 1);
        var columns = row.ColumnDefinitions.Count;
        Assert.All(row.Children, c => Assert.InRange(Grid.GetColumn(c), 0, columns - 1));
    }

    [AvaloniaFact]
    public void The_round_strip_carries_the_timer_the_buzz_toggle_and_the_letter_picker()
    {
        var names = Builder().GetVisualDescendants().OfType<Control>()
                             .Select(AutomationProperties.GetName).ToList();
        Assert.Contains("Countdown for round 1", names);
        Assert.Contains("Round 1 is a buzz round", names);
        Assert.Contains("First-letter theme for round 1", names);
    }

    [AvaloniaFact]
    public void A_letter_theme_survives_a_save_and_reload()
    {
        var view = Builder();
        var ev = new LiveEvent
        {
            Name = "Letters",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 4 },
                      new NightRound { Kind = GameMode.Classic, Count = 4 }],
            RoundLetters = ["B", ""],
        };
        view.LoadEventForTesting(ev);
        Dispatcher.UIThread.RunJobs();
        Assert.Equal("B", view.RoundLettersForTesting[0]);
        Assert.Equal("", view.RoundLettersForTesting[1]);
    }
}
