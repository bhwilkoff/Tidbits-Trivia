using System;
using System.Collections.Generic;
using System.Linq;
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
    }

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
