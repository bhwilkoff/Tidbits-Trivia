using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class PlayView : UserControl
{
    // Every consumer mode now has a built answer surface: MCQ shapes + Stake +
    // numeric (Closest Call) + free-text (Name It) + reorder (In Order) +
    // Match Up + Name as Many + Picture ID (image pipeline).
    private static readonly GameMode[] Offered =
    {
        GameMode.Classic, GameMode.TimeAttack, GameMode.Survival, GameMode.Stake,
        GameMode.Sweep, GameMode.Ladder, GameMode.OddOneOut, GameMode.ThisOrThat,
        GameMode.ClosestCall, GameMode.TypeAnswer, GameMode.Ordering,
        GameMode.Matching, GameMode.Enumerate, GameMode.PictureId,
    };

    public PlayView()
    {
        InitializeComponent();
        CategoryPicker.ItemsSource = TriviaCategory.All;
        CategoryPicker.ItemTemplate = new FuncDataTemplate<TriviaCategory>((c, _) =>
            new TextBlock { Text = c?.Name ?? "" });
        CategoryPicker.SelectedIndex = 0; // Mixed Bag

        foreach (var m in Offered)
        {
            var mode = m;
            var btn = new Button
            {
                Content = mode.Title(),
                Margin = new Avalonia.Thickness(0, 0, 10, 10),
                Padding = new Avalonia.Thickness(16, 11),
            };
            btn.Click += (_, _) => StartGame(mode);
            ModesPanel.Children.Add(btn);
        }

        // Trivia Night presets (Quick / Pub / The Works) — each launches a solo,
        // self-paced night of themed rounds with a round interstitial.
        foreach (var preset in NightPlan.Presets)
        {
            var plan = preset.Plan;
            var card = new Button
            {
                Margin = new Avalonia.Thickness(0, 0, 10, 10), Padding = new Avalonia.Thickness(16, 12),
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Content = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = preset.Name, FontWeight = Avalonia.Media.FontWeight.Bold },
                        new TextBlock { Text = preset.Blurb, FontSize = 12, Opacity = 0.65 },
                    },
                },
            };
            card.Click += (_, _) => StartNight(plan);
            NightPanel.Children.Add(card);
        }

        BuildVersus();
        BuildDaily();
        BuildPresets();
        BuildWeakSpot();
        BuildMarathonCard();
        BuildExpeditionsCard();
        BuildLinkWallCard();
    }

    // MARK: - Tidbits Club: Weak-Spot Arena (docs/CLUB-FEATURES-BUILD.md "Feature 1")

    /// A round built entirely from the player's own miss history — Club-gated, never a
    /// free Customize pick and never a remembered/random default (the `Offered` array
    /// above never lists it). Members launch it; non-members see a real preview (a
    /// genuine missed fact when one exists, else an honest static line) and the
    /// existing Club paywall — never a blank wall.
    private void BuildWeakSpot()
    {
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var subtitle = isClub
            ? GameMode.WeakSpot.Blurb()
            : WeakSpotArena.PreviewLine(data.Records)
              ?? "Your misses, turned into a round you can actually close.";

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "WEAK-SPOT ARENA", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = Avalonia.Media.FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? "Play" : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnWeakSpotAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        WeakSpotPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members launch the arena directly; everyone else sees the existing paywall
    /// (the app's established modal idiom — FAContentDialog, never an interstitial).
    private async void OnWeakSpotAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildWeakSpot(); // reflect a purchase/restore made from inside the dialog
            return;
        }
        await StartWeakSpotAsync();
    }

    /// Builds a fresh round from the current miss history and launches it — rebuilt
    /// (not replayed verbatim) on Play Again too, since resolved misses change what
    /// belongs in the next round.
    private async Task StartWeakSpotAsync()
    {
        var data = GameData.Shared.Value;
        var round = WeakSpotArena.Build(data.Records, data.Sources.Corpus);
        if (round.Questions.Count < WeakSpotArena.PlayableFloor)
        {
            var dialog = new FAContentDialog
            {
                Title = "Not enough misses yet",
                Content = new TextBlock
                {
                    Text = "Play a few rounds first — your misses become your arena.",
                    TextWrapping = TextWrapping.Wrap, MaxWidth = 360,
                },
                CloseButtonText = "Back",
            };
            await dialog.ShowAsync();
            return;
        }

        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; BuildWeakSpot(); };
        vm.PlayAgainRequested += () => _ = StartWeakSpotAsync();
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.WeakSpot, TriviaCategory.Named("mixed"), round.Questions, round.Reasons);
    }

    // MARK: - Tidbits Club: Marathon (docs/CLUB-FEATURES-BUILD.md "Feature 3")

    /// A 200-question graded endurance run that RESUMES ACROSS SESSIONS — Club-
    /// gated, never a free Customize pick (the `Offered` array above never lists
    /// it). Members launch/resume; non-members see a real preview (their last
    /// run's accuracy once they have Club history, else an honest static pitch —
    /// Marathon is Club-only end to end, so there's no free-tier sample) and the
    /// existing Club paywall — never a blank wall.
    private void BuildMarathonCard()
    {
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var run = Marathon.InProgress(data.Records);
        var subtitle = isClub
            ? (run is not null
                ? $"Question {run.CurrentIndex + 1} of {run.Total} — tap to resume"
                : Marathon.PreviewLine(data.Records) ?? GameMode.Marathon.Blurb())
            : "See exactly where you stand — e.g. Geography 91% · History 64% — across a 200-question run you can pause and resume anytime.";

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "MARATHON", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = Avalonia.Media.FontWeight.Black, Foreground = Brushes.White },
            });
        }
        else if (run is not null)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#13B6C9")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "RESUME", FontSize = 11, FontWeight = Avalonia.Media.FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? (run is not null ? "Resume" : "Play") : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnMarathonAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        MarathonPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members with a run in progress get a Resume/Start-over choice (an
    /// FAContentDialog); with no run, they launch straight into a fresh one.
    /// Non-members see the existing paywall — never a blank wall.
    private async void OnMarathonAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildMarathonCard(); // reflect a purchase/restore made from inside the dialog
            return;
        }

        var run = Marathon.InProgress(data.Records);
        if (run is not null)
        {
            var dialog = new FAContentDialog
            {
                Title = "Marathon in progress",
                Content = new TextBlock
                {
                    Text = $"Question {run.CurrentIndex + 1} of {run.Total} — resume where you left off, or start a fresh run.",
                    TextWrapping = TextWrapping.Wrap, MaxWidth = 360,
                },
                PrimaryButtonText = "Resume", SecondaryButtonText = "Start Over", CloseButtonText = "Cancel",
            };
            var result = await dialog.ShowAsync();
            if (result == FAContentDialogResult.Primary) await StartMarathonAsync(startOver: false);
            else if (result == FAContentDialogResult.Secondary) await StartMarathonAsync(startOver: true);
            return;
        }
        await StartMarathonAsync(startOver: false);
    }

    /// Resumes the in-progress run unless `startOver` (or none exists), loading
    /// only the REMAINING questions — the HUD adds the offset back in so the
    /// player always sees their true position out of the full run.
    private async Task StartMarathonAsync(bool startOver)
    {
        var data = GameData.Shared.Value;
        var run = startOver
            ? Marathon.StartNew(data.Records, data.Sources.Corpus)
            : Marathon.InProgress(data.Records) ?? Marathon.StartNew(data.Records, data.Sources.Corpus);
        var offset = run.CurrentIndex;
        var remainingIds = Marathon.ResumeIds(run);
        if (remainingIds.Count == 0)
        {
            // Edge case only (a run already at its full length without having
            // been finished) — close it out rather than show a blank round.
            Marathon.Finish(data.Records, run);
            BuildMarathonCard();
            return;
        }

        var questions = data.Sources.Corpus.Questions(remainingIds);
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records, run);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; BuildMarathonCard(); };
        vm.PlayAgainRequested += () => _ = StartMarathonAsync(startOver: true);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Marathon, TriviaCategory.Named("mixed"), questions, marathonOffset: offset);
    }

    // MARK: - Tidbits Club: Expeditions (docs/CLUB-FEATURES-BUILD.md "Feature 5")

    /// A multi-week structured campaign through one domain — Club-marked, but UNLIKE
    /// Weak-Spot/Marathon this card's action ALWAYS opens the hub (never the paywall
    /// directly): the hub + a campaign's map are a real preview reachable by
    /// everyone, and only tapping Play on a stage is Club-gated
    /// (docs/CLUB-FEATURES-BUILD.md "Feature 5" — "never a blank wall").
    private void BuildExpeditionsCard()
    {
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var available = Expeditions.Available(data.Records);
        int started = available.Count(a => a.Progress is not null);
        var subtitle = started > 0
            ? $"{started} of {available.Count} expeditions underway."
            : Expeditions.PreviewLine();

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "EXPEDITIONS", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = Avalonia.Media.FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        // Always "Open" — the hub is a real preview reachable by everyone.
        var action = new Button { Content = "Open", Classes = { "accent", "compact" }, VerticalAlignment = VerticalAlignment.Center };
        action.Click += (_, _) => OnExpeditionsAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        ExpeditionsPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    private async void OnExpeditionsAction()
    {
        var data = GameData.Shared.Value;
        await ExpeditionsDialog.ShowAsync(data.Records, StartExpeditionStage);
        BuildExpeditionsCard(); // reflect progress/certificates changed while the dialog was open
    }

    /// Launches one stage as a NORMAL Classic round with a difficulty-banded custom
    /// question set — a stage writes a genuine GameRecord (unlike Marathon), and
    /// GameViewModel layers the pass/fail/certificate tracking on top via
    /// `Expeditions.RecordStageResult`. Continuing/retrying/finishing all return to
    /// the expedition's map so the player sees the result reflected immediately.
    private async void StartExpeditionStage(Expedition expedition, int stageIndex)
    {
        var data = GameData.Shared.Value;
        var stage = expedition.Stages.First(s => s.Index == stageIndex);
        var questions = Expeditions.StartStage(data.Sources.Corpus, expedition, stageIndex);
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records, expeditionStage: (expedition, stageIndex));
        vm.Closed += () =>
        {
            GameHost.Content = null; Landing.IsVisible = true; BuildExpeditionsCard();
            _ = ExpeditionsDialog.ShowAsync(data.Records, StartExpeditionStage, openExpeditionId: expedition.Id);
        };
        vm.PlayAgainRequested += () => StartExpeditionStage(expedition, stageIndex); // retry the SAME stage
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named(stage.CategoryId), questions);
    }

    // MARK: - Tidbits Club: Link Wall (docs/CLUB-FEATURES-BUILD.md "Feature 6")

    /// A NYT-Connections-style SECOND daily — Club-marked, sitting right next to the
    /// free Daily Tidbit above (which this never touches). Members open straight into
    /// today's board (or its result, if already played); non-members see a real
    /// preview — today's easiest group's actual label, generated fresh from the
    /// bundled corpus (public content, not a nag) — and the existing Club paywall,
    /// never a blank wall.
    private void BuildLinkWallCard()
    {
        var data = GameData.Shared.Value;
        bool isClub = data.Entitlement.IsClub;
        var day = QuestionProvider.DayKey();
        var puzzle = LinkWall.Puzzle(day, LinkWallMatchQuestions());
        var todayResult = data.Records.LinkWall.GetValueOrDefault(day);

        string subtitle;
        if (isClub)
        {
            subtitle = todayResult switch
            {
                { Completed: true, Won: true } => "Solved today's wall — see the recap.",
                { Completed: true, Won: false } => "See today's groups.",
                { Completed: false } => "In progress — tap to keep going.",
                _ => "4 groups of 4. One guess at a time, 4 mistakes allowed.",
            };
        }
        else
        {
            var previewLabel = puzzle?.Groups.OrderBy(g => g.Difficulty).FirstOrDefault()?.Label;
            subtitle = previewLabel is not null
                ? $"Today's board includes \"{previewLabel}\" — find all four groups."
                : "A second daily: 16 facts, 4 hidden groups. Find them all.";
        }

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock { Text = "LINK WALL", Classes = { "body-strong" } });
        if (!isClub)
        {
            titleRow.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.Parse("#FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(6),
                Padding = new Avalonia.Thickness(7, 2),
                Child = new TextBlock { Text = "CLUB", FontSize = 11, FontWeight = Avalonia.Media.FontWeight.Black, Foreground = Brushes.White },
            });
        }

        var textStack = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        textStack.Children.Add(titleRow);
        textStack.Children.Add(new TextBlock { Text = subtitle, Classes = { "caption" }, TextWrapping = TextWrapping.Wrap });

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(textStack);

        var action = new Button
        {
            Content = isClub ? "Play" : "Join Club",
            Classes = { "accent", "compact" },
            VerticalAlignment = VerticalAlignment.Center,
        };
        action.Click += (_, _) => OnLinkWallAction();
        Grid.SetColumn(action, 1);
        grid.Children.Add(action);

        LinkWallPanel.Content = new Border { Classes = { "card" }, Child = grid };
    }

    /// Members open straight into today's board (the FAContentDialog board/result
    /// swap); non-members see the existing paywall — never a blank wall.
    private async void OnLinkWallAction()
    {
        var data = GameData.Shared.Value;
        if (!data.Entitlement.IsClub)
        {
            var dialog = new FAContentDialog
            {
                Content = new ScrollViewer { Content = new ClubPaywallView(), MaxWidth = 520, MaxHeight = 640 },
                CloseButtonText = "Close",
            };
            await dialog.ShowAsync();
            BuildLinkWallCard(); // reflect a purchase/restore made from inside the dialog
            return;
        }
        await LinkWallDialog.ShowAsync(data.Records, LinkWallMatchQuestions(), QuestionProvider.DayKey());
        BuildLinkWallCard(); // reflect today's progress/result changed while the dialog was open
    }

    /// The bundled match.json rows Link Wall's generator draws from — the same
    /// enrichment source that already powers the free Match-Up mode.
    private static List<Question> LinkWallMatchQuestions() =>
        GameData.Shared.Value.Sources.Enrich(GameMode.Matching).Questions("mixed", new HashSet<string>(), 100_000);

    /// Saved Custom Mix presets ("My Mix") — each replays its modes + category,
    /// or can be removed. Parity with the web/Mac presets list.
    private void BuildPresets()
    {
        PresetsPanel.Children.Clear();
        var presets = GameData.Shared.Value.Presets.All;
        if (presets.Count == 0) return;

        PresetsPanel.Children.Add(new TextBlock
        {
            Text = "Your mixes", FontWeight = Avalonia.Media.FontWeight.Bold, FontSize = 15,
            Margin = new Avalonia.Thickness(0, 6, 0, 2),
        });
        foreach (var p in presets)
        {
            var preset = p;
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
            var label = new TextBlock
            {
                Text = $"{preset.Name} · {preset.Modes.Count} modes",
                VerticalAlignment = VerticalAlignment.Center,
            };
            grid.Children.Add(label);

            var play = new Button { Content = "Play", Classes = { "accent", "compact" } };
            play.Click += (_, _) => PlayPreset(preset);
            Grid.SetColumn(play, 1);
            grid.Children.Add(play);

            var remove = new Button
            {
                Content = "Remove", Classes = { "compact" },
                Margin = new Avalonia.Thickness(8, 0, 0, 0),
            };
            remove.Click += (_, _) => { GameData.Shared.Value.Presets.Remove(preset.Id); BuildPresets(); };
            Grid.SetColumn(remove, 2);
            grid.Children.Add(remove);

            PresetsPanel.Children.Add(new Border
            {
                BorderBrush = new SolidColorBrush(Color.Parse("#22808080")),
                BorderThickness = new Avalonia.Thickness(1), CornerRadius = new Avalonia.CornerRadius(10),
                Padding = new Avalonia.Thickness(14, 10), Child = grid,
            });
        }
    }

    private void PlayPreset(GamePreset preset) =>
        StartMix(preset.Modes, TriviaCategory.Named(preset.CategoryId));

    /// Versus-CPU opponents: the three fixed bots + The House (adapts to the
    /// player's lifetime accuracy). Every button says CPU.
    private void BuildVersus()
    {
        var records = GameData.Shared.Value.Records;
        int correct = records.Games.Sum(g => g.Correct), total = records.Games.Sum(g => g.Total);
        double accuracy = total == 0 ? 0.6 : (double)correct / total;

        var opponents = new[]
        {
            Bots.All["rookie"], Bots.All["regular"], Bots.All["ace"], Bots.House(accuracy),
        };
        foreach (var b in opponents)
        {
            var bot = b;
            var btn = new Button
            {
                Content = $"{bot.Name} · CPU",
                Margin = new Avalonia.Thickness(0, 0, 10, 10), Padding = new Avalonia.Thickness(16, 11),
            };
            btn.Click += (_, _) => StartVersus(bot);
            VersusPanel.Children.Add(btn);
        }
    }

    private async void StartVersus(Bot bot)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var player = new GameViewModel(engine, records: null); // versus matches don't write records
        var versus = new VersusViewModel(player, bot);
        player.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; versus.Dispose(); };
        player.PlayAgainRequested += () => StartVersus(bot); // rematch
        Landing.IsVisible = false;
        GameHost.Content = new VersusView { DataContext = versus };
        await engine.Start(GameMode.Classic, SelectedCategory());
    }

    /// Today's Daily (play-once — a done card once completed) plus a "Previous
    /// Tidbits" archive of the last 14 days: past days are playable (deterministic
    /// day-key seed) and never bump the streak (enforced in RecordsStore).
    private void BuildDaily()
    {
        DailyPanel.Children.Clear();
        var log = GameData.Shared.Value.Daily;
        var today = QuestionProvider.DayKey();

        for (int i = 0; i < 14; i++)
        {
            var date = DateTime.Now.Date.AddDays(-i);
            var day = QuestionProvider.DayKey(date);
            bool isToday = day == today;
            var result = log.Result(day);
            var label = isToday ? "Today" : date.ToString("ddd, MMM d");

            var row = new Border
            {
                Background = isToday && result is null ? new SolidColorBrush(Color.Parse("#FF5C35")) : null,
                CornerRadius = new Avalonia.CornerRadius(10),
                BorderBrush = result is not null || !isToday ? new SolidColorBrush(Color.Parse("#22808080")) : null,
                BorderThickness = new Avalonia.Thickness(isToday && result is null ? 0 : 1),
                Padding = new Avalonia.Thickness(16, 12), Margin = new Avalonia.Thickness(0, 0, 0, 6),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            bool heroToday = isToday && result is null;
            var labelBlock = new TextBlock
            {
                Text = label, FontWeight = Avalonia.Media.FontWeight.SemiBold, VerticalAlignment = VerticalAlignment.Center,
            };
            if (heroToday) labelBlock.Foreground = Brushes.White; // else inherit the themed default
            grid.Children.Add(labelBlock);

            if (result is not null)
            {
                var done = new TextBlock
                {
                    Text = $"{result.Correct}/{result.Total} · {result.Score} pts", VerticalAlignment = VerticalAlignment.Center,
                    Opacity = 0.75, FontSize = 13,
                };
                Grid.SetColumn(done, 1);
                grid.Children.Add(done);
            }
            else
            {
                var d = day;
                var play = new Button
                {
                    Content = isToday ? "Play today's Tidbit" : "Play",
                    Padding = new Avalonia.Thickness(16, 8),
                    Classes = { "accent" },
                };
                play.Click += (_, _) => StartDaily(d);
                Grid.SetColumn(play, 1);
                grid.Children.Add(play);
            }
            row.Child = grid;
            DailyPanel.Children.Add(row);
        }
    }

    private async void StartDaily(string day)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; BuildDaily(); };
        vm.Finished += () =>
        {
            var s = engine.Summary;
            data.Daily.Record(s.DailyDay ?? day, s.Score, s.Correct, s.Total);
            // Contribute to the global Daily board (docs/DAILY-BOARD-CONTRACT.md) — a
            // Windows player is ranked worldwide. Board-VIEWING UI is a fast-follow.
            var id = data.Identity.Current;
            _ = Tidbits.Core.Networking.DailyBoardApi.SubmitAsync(
                data.Rtdb, data.Sources.Corpus, s, id.Name, id.AvatarSeed);
        };
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        await engine.Start(GameMode.Daily, TriviaCategory.Named("mixed"), dailyDay: day);
    }

    private TriviaCategory SelectedCategory() =>
        CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");

    // Modes that use the standard MCQ surface, where a woven review question (a
    // 4-option MCQ) fits — spaced re-asking skips Daily + the non-MCQ shapes.
    private static bool Reviewable(GameMode m) => m is GameMode.Classic or GameMode.TimeAttack
        or GameMode.Survival or GameMode.Sweep or GameMode.Ladder or GameMode.OddOneOut or GameMode.ThisOrThat;

    private async void StartGame(GameMode mode, TriviaCategory? category = null)
    {
        var cat = category ?? SelectedCategory();
        var data = GameData.Shared.Value;
        // Quick-Play memory (parity): remember the last single play so Quick Play replays it.
        data.Settings.LastMode = mode.ToString();
        data.Settings.LastCategoryId = cat.Id;
        data.Settings.Save();
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () =>
        {
            GameHost.Content = null;
            Landing.IsVisible = true;
        };
        // Play Again restarts the exact mode + category that was just played.
        vm.PlayAgainRequested += () => StartGame(vm.Summary.Mode, vm.Summary.Category);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        // Spaced re-asking: weave due missed facts into MCQ games (opt-out via Settings).
        var review = data.Settings.ReviewEnabled && Reviewable(mode) ? data.Records.DueReview() : null;
        await engine.Start(mode, cat, review);
    }

    private async void StartNight(NightPlan plan)
    {
        var cat = SelectedCategory();
        var data = GameData.Shared.Value;
        var questions = await data.Provider.NightQuestions(plan, cat);
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; };
        vm.PlayAgainRequested += () => StartNight(plan);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartNight(plan, cat, questions);
    }

    /// Online Quick Match (2.21) — find a real opponent, same questions, best score wins.
    private void OnQuickMatch(object? sender, RoutedEventArgs e)
    {
        var data = GameData.Shared.Value;
        var vm = new QuickMatchViewModel(new QuickMatchClient(data.Rtdb), data);
        var view = new QuickMatchView { DataContext = vm };
        view.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; vm.Dispose(); };
        Landing.IsVisible = false;
        GameHost.Content = view;
        vm.Start(data.PlayerName);
    }

    private void OnPassAndPlay(object? sender, RoutedEventArgs e)
    {
        var party = new PartyView();
        party.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; };
        Landing.IsVisible = false;
        GameHost.Content = party;
    }

    /// Quick Play replays your last single mode + category (parity with web
    /// quickPlayTarget), defaulting to Classic/Mixed on a fresh install.
    private void OnQuickPlay(object? sender, RoutedEventArgs e)
    {
        var s = GameData.Shared.Value.Settings;
        var mode = Enum.TryParse<GameMode>(s.LastMode, out var m) && Offered.Contains(m) ? m : GameMode.Classic;
        var cat = TriviaCategory.Named(s.LastCategoryId ?? "mixed");
        StartGame(mode, cat);
    }

    /// Surprise me — a random offered mode + a random category, matching the Mac
    /// (surpriseMe) and web (data-surprise) parity. The offered set already excludes
    /// Daily/Night/Mix, so no extra filtering is needed.
    private void OnSurprise(object? sender, RoutedEventArgs e)
    {
        var mode = Offered[Random.Shared.Next(Offered.Length)];
        var cats = TriviaCategory.All.ToArray();
        var cat = cats[Random.Shared.Next(cats.Length)];
        StartGame(mode, cat);
    }

    /// Customize a mix (2.6): pick multiple modes + a category, then Play the mix
    /// or Save it as a named preset. Parity with the web customize dialog / Mac.
    private async void OnCustomize(object? sender, RoutedEventArgs e)
    {
        var checks = new List<(GameMode mode, CheckBox box)>();
        var modesPanel = new WrapPanel();
        foreach (var m in Offered)
        {
            var box = new CheckBox { Content = m.Title(), Margin = new Avalonia.Thickness(0, 0, 12, 6) };
            checks.Add((m, box));
            modesPanel.Children.Add(box);
        }

        var catPicker = new ComboBox { MinWidth = 160 };
        catPicker.ItemsSource = TriviaCategory.All;
        catPicker.ItemTemplate = new FuncDataTemplate<TriviaCategory>((c, _) => new TextBlock { Text = c?.Name ?? "" });
        catPicker.SelectedItem = SelectedCategory();

        var nameBox = new TextBox { Watermark = "Name this mix (to save)", MaxLength = 40 };

        var content = new StackPanel
        {
            Spacing = 12, MinWidth = 360,
            Children =
            {
                new TextBlock { Text = "Pick the modes to shuffle together.", Opacity = 0.75, TextWrapping = TextWrapping.Wrap },
                modesPanel,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal, Spacing = 10,
                    Children =
                    {
                        new TextBlock { Text = "Category:", VerticalAlignment = VerticalAlignment.Center, Opacity = 0.7 },
                        catPicker,
                    },
                },
                nameBox,
            },
        };

        var dialog = new FAContentDialog
        {
            Title = "Customize a mix", Content = content,
            PrimaryButtonText = "Play mix", SecondaryButtonText = "Save preset", CloseButtonText = "Cancel",
        };

        var result = await dialog.ShowAsync();
        var picked = checks.Where(c => c.box.IsChecked == true).Select(c => c.mode).ToList();
        var cat = catPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        if (picked.Count == 0) return;

        if (result == FAContentDialogResult.Primary)
        {
            StartMix(picked, cat);
        }
        else if (result == FAContentDialogResult.Secondary && !string.IsNullOrWhiteSpace(nameBox.Text))
        {
            GameData.Shared.Value.Presets.Save(nameBox.Text!, picked, cat.Id);
            BuildPresets();
        }
    }

    private async void StartMix(IReadOnlyList<GameMode> modes, TriviaCategory category)
    {
        var data = GameData.Shared.Value;
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, data.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; };
        vm.PlayAgainRequested += () => StartMix(modes, category);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        await engine.StartMix(modes, category);
    }
}
