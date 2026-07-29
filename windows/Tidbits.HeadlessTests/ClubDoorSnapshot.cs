using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Rule R-CLUB-1 (docs/iOS-DESIGN.md §5.2a — the rule is cross-platform): the app shows
/// **at most one Club entry point, and it lives on Home**. Every Club feature is reached
/// from inside that door and from nowhere else.
///
/// These replace fifteen older snapshots that asserted the opposite — a Club card on Play
/// for Link Wall / Weak-Spot / Marathon / Expeditions, and three more in Records. Those
/// tests encoded the design the owner changed on 2026-07-29: seven visible locks made a
/// mostly-free app read as a mostly-paywalled one. The feature UIs themselves (board, hub,
/// map, list, detail) are unchanged and still covered by the remaining tests in those files.
///
/// `PlayView` reads `TIDBITS_CLUB` (via `DebugHooks.ForceClub`) at construction, so these
/// are env-sensitive — same discipline as the snapshots they replace.
[Collection("EnvSensitive")]
public class ClubDoorSnapshot
{
    private static List<string?> TextsOf(Control root) =>
        root.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();

    /// The six titles that used to be scattered across Play and Records. None of them may
    /// appear on a landing surface any more — that is the whole point of the rule.
    private static readonly string[] FeatureTitles =
    {
        "LINK WALL", "WEAK-SPOT ARENA", "MARATHON", "EXPEDITIONS",
        "STORY ARCHIVE", "KNOWLEDGE ATLAS", "MARATHON HISTORY",
    };

    [AvaloniaFact]
    public void Play_home_shows_exactly_one_club_entry_point_for_a_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
        var win = new Window { Width = 900, Height = 1400, Content = new PlayView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Equal(1, texts.Count(t => t == "TIDBITS CLUB"));
        foreach (var title in FeatureTitles)
        {
            Assert.DoesNotContain(title, texts);
        }
    }

    [AvaloniaFact]
    public void Play_home_shows_the_same_single_door_to_a_non_member_and_never_a_price()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
        var win = new Window { Width = 900, Height = 1400, Content = new PlayView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Equal(1, texts.Count(t => t == "TIDBITS CLUB"));
        foreach (var title in FeatureTitles)
        {
            Assert.DoesNotContain(title, texts);
        }
        // The door explains, it does not sell: no CLUB chips, no plan prices on Home.
        Assert.DoesNotContain("CLUB", texts);
        Assert.DoesNotContain(texts, t => t is not null && t.Contains('$'));
        Assert.Contains(texts, t => t is not null && t.Contains("Everything else in Tidbits is free"));
    }

    [AvaloniaFact]
    public void Records_is_free_tier_only_and_offers_no_club_drill_ins()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
        var win = new Window { Width = 900, Height = 1400, Content = new RecordsView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.DoesNotContain("STORY ARCHIVE", texts);
        Assert.DoesNotContain("MARATHON HISTORY", texts);
        Assert.DoesNotContain("KNOWLEDGE ATLAS", texts);
        Assert.DoesNotContain("TIDBITS CLUB", texts);   // the door is on Home, and only there
        Assert.DoesNotContain("CLUB", texts);
    }
}
