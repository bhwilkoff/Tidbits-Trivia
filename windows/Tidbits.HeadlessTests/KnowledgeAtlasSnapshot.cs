using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md "Feature 4") — the Records
/// entry-point card (Club-marked, R-REC-1) and the atlas's pure rendering
/// (`KnowledgeAtlasUi`, mirrors `StoryArchiveUi`/`ClubPaywallUi`'s headless-testable
/// static-builder pattern). Windows is the last of six platforms.
[Collection("EnvSensitive")]
public class KnowledgeAtlasSnapshot
{
    private static string Art()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static List<string?> TextsOf(Control root) =>
        root.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();

    private static GameRecord G(string categoryId, int correct, int total, int monthsAgo) => new()
    {
        CategoryId = categoryId, Score = correct, Correct = correct, Total = total,
        Date = DateTime.UtcNow.AddMonths(-monthsAgo),
    };

    // MARK: - Records dashboard card (reads GameData.Shared, like the Story Archive card)

    private static RecordsStore StoreWithHistory(IEnumerable<GameRecord> games)
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-atlas-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(new RecordsData { Games = games.ToList() }));
        return new RecordsStore(path);
    }

    // The Knowledge Atlas CARD (BuildKnowledgeAtlasCard) reads `GameData.Shared.Value`
    // directly — the same established pattern as the Story Archive/Marathon History
    // cards (see RecordsView.axaml's comment: "built in code-behind since it reads
    // live entitlement state, not the VM"), NOT the `RecordsStore` passed via
    // DataContext. So these two tests assert what's true regardless of that shared,
    // process-lifetime state (empty on a fresh CI checkout): the title, the correct
    // action button for club/non-club, and — for non-members — a real-or-honest line
    // that's never a blank wall. `StoreWithHistory` only seeds the DataContext-bound
    // dashboard list below the card (mirrors StoryArchiveSnapshot's StoreWithOneGame).

    [AvaloniaFact]
    public void Records_shows_the_knowledge_atlas_card_for_a_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
        var store = StoreWithHistory(new[] { G("history", 8, 10, 1) });
        var win = new Window { Width = 900, Height = 1000, Content = new RecordsView { DataContext = new RecordsViewModel(store) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("KNOWLEDGE ATLAS", texts);
        var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Open").ToList();
        Assert.NotEmpty(buttons);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-knowledge-atlas-member.png"));
    }

    [AvaloniaFact]
    public void Records_shows_the_club_chip_and_a_real_or_honest_preview_for_a_non_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
        var store = StoreWithHistory(new[] { G("history", 9, 10, 1), G("science", 2, 10, 1) });
        var win = new Window { Width = 900, Height = 1000, Content = new RecordsView { DataContext = new RecordsViewModel(store) } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("KNOWLEDGE ATLAS", texts);
        Assert.Contains("CLUB", texts); // non-member -> chip
        var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Join Club").ToList();
        Assert.NotEmpty(buttons);
        // Never a blank wall: some subtitle line renders regardless of local history.
        Assert.Contains(texts, t => t is not null && t.Contains("Club", StringComparison.Ordinal));

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "records-knowledge-atlas-non-member.png"));
    }

    // MARK: - Atlas rendering (KnowledgeAtlasUi — pure, headless-testable)

    [AvaloniaFact]
    public void Empty_atlas_shows_the_not_enough_history_message()
    {
        var content = KnowledgeAtlasUi.BuildAtlas(
            domains: Array.Empty<KnowledgeAtlas.DomainAtlasEntry>(),
            decaying: Array.Empty<KnowledgeAtlas.DecayEntry>(),
            onPlay: _ => { });

        var win = new Window { Width = 480, Height = 260, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains(TextsOf(win), t => t is not null && t.Contains("Atlas fills in", StringComparison.Ordinal));
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "knowledge-atlas-empty.png"));
    }

    [AvaloniaFact]
    public void Domain_row_shows_accuracy_sample_size_and_a_trajectory_badge()
    {
        var entry = new KnowledgeAtlas.DomainAtlasEntry("history", Correct: 8, Total: 10, RecentAccuracy: 0.4, PriorAccuracy: 0.8);
        string? played = null;
        var content = KnowledgeAtlasUi.BuildDomainRow(entry, () => played = entry.CategoryId);

        var win = new Window { Width = 480, Height = 220, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("History", texts);
        Assert.Contains("80%", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("8/10 answered", StringComparison.Ordinal));
        Assert.Contains(texts, t => t is not null && t.StartsWith("▼", StringComparison.Ordinal)); // decayed -40pts

        var button = win.GetVisualDescendants().OfType<Button>().First();
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal("history", played);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "knowledge-atlas-domain-row.png"));
    }

    [AvaloniaFact]
    public void Decay_row_shows_past_vs_recent_and_a_shore_it_up_button_that_fires_onPlay()
    {
        var entry = new KnowledgeAtlas.DecayEntry("science", PastAccuracy: 0.8, RecentAccuracy: 0.5);
        string? played = null;
        var content = KnowledgeAtlasUi.BuildDecayRow(entry, () => played = entry.CategoryId);

        var win = new Window { Width = 480, Height = 140, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Science", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("80% then", StringComparison.Ordinal));
        Assert.Contains("Shore it up", texts);

        var button = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Shore it up");
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal("science", played);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "knowledge-atlas-decay-row.png"));
    }

    [AvaloniaFact]
    public void Full_atlas_renders_domains_and_the_decay_radar_section_together()
    {
        var domains = new[]
        {
            new KnowledgeAtlas.DomainAtlasEntry("history", 8, 10, 0.4, 0.8),
            new KnowledgeAtlas.DomainAtlasEntry("science", 8, 10, 0.9, 0.8),
        };
        var decaying = new[] { new KnowledgeAtlas.DecayEntry("history", 0.8, 0.4) };

        var content = KnowledgeAtlasUi.BuildAtlas(domains, decaying, onPlay: _ => { });
        var win = new Window { Width = 520, Height = 700, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("History", texts);
        Assert.Contains("Science", texts);
        Assert.Contains("Decay radar", texts);
        Assert.Contains("Shore it up", texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "knowledge-atlas-full.png"));
    }
}
