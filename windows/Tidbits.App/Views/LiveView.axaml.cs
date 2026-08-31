using System;
using System.Linq;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class LiveView : UserControl
{
    public LiveView()
    {
        InitializeComponent();

        CategoryPicker.ItemsSource = TriviaCategory.All;
        CategoryPicker.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<TriviaCategory>(
            (c, _) => new TextBlock { Text = c?.Name ?? "" });
        CategoryPicker.SelectedIndex = 0; // Mixed Bag

        foreach (var (name, blurb, plan) in NightPlan.Presets)
        {
            var p = plan;
            var btn = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Avalonia.Thickness(18, 14),
                Content = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = name, FontWeight = Avalonia.Media.FontWeight.Bold, FontSize = 16 },
                        new TextBlock { Text = blurb, FontSize = 12, Opacity = 0.65 },
                    },
                },
            };
            btn.Click += (_, _) => StartHosting(p, name);
            PresetsPanel.Children.Add(btn);
        }

        RoundModeBox.ItemsSource = NightPlan.AllKinds;
        RoundModeBox.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<GameMode>(
            (m, _) => new TextBlock { Text = m.Title() });
        RoundModeBox.SelectedIndex = 0;
        RoundCountBox.ItemsSource = new[] { 3, 4, 5, 6, 8 };
        RoundCountBox.SelectedIndex = 1; // 4
        // Index 0 = one-off; 1..7 = Sunday..Saturday (DayOfWeek 0..6 = index-1).
        WeekdayBox.ItemsSource = new[] { "One-off", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
        WeekdayBox.SelectedIndex = 0;
        BuildSavedEvents();

        // TIDBITS_LIVE_HOST=<preset name> — open a real hosted room straight from launch,
        // the Windows twin of Apple's TIDBITS_NIGHT_HOST and Android's tidbits_night_host.
        // Without it Windows was the one platform that could not be DRIVEN as a host: every
        // route into StartHosting is a Click, so a harness could only get here by blind
        // coordinate tapping. That is why "every platform can host, every platform can join"
        // had never actually been tested in the Windows-hosts direction — not because it
        // failed, but because nothing could ask the question.
        // TIDBITS_LIVE_JOIN=<code> — join a room someone ELSE is hosting. The most
        // consequential of the missing hooks: every other platform could be told to
        // join, so "every platform joins every other platform's game" had been proven
        // in every direction except one — nothing could ask Windows to join at all.
        var joinCode = Services.LaunchHooks.LiveJoin;
        if (joinCode is not null)
        {
            Loaded += (_, _) => JoinAsPlayer(joinCode, Services.LaunchHooks.LiveName);
            return;
        }

        // TIDBITS_NIGHT_HOST=1 — host the default night. Apple and Android both had
        // this; Windows could reach the host seat only through a Click handler.
        var wantHost = Services.LaunchHooks.NightHost
            ? NightPlan.Presets[0].Name
            : Services.LaunchHooks.LiveHost;
        if (!string.IsNullOrWhiteSpace(wantHost))
        {
            var (name, _, plan) = NightPlan.Presets.FirstOrDefault(
                x => string.Equals(x.Item1, wantHost, StringComparison.OrdinalIgnoreCase));
            // Any unrecognised value hosts the first preset rather than silently doing
            // nothing — a harness that asked for a host and got the setup screen would
            // grade the setup screen.
            if (plan is null) (name, _, plan) = NightPlan.Presets[0];
            Loaded += (_, _) => StartHosting(plan, name);
        }
    }

    // The rounds being composed for a custom event (+ an index-aligned host note).
    private readonly System.Collections.Generic.List<NightRound> _rounds = new();
    private readonly System.Collections.Generic.List<string> _notes = new();
    private readonly System.Collections.Generic.List<int> _timers = new();   // per-round countdown, 0 = untimed
    private static readonly int[] TimerChoices = { 0, 30, 45, 60, 90, 120 };
    private static int TimerIndex(int seconds) => System.Math.Max(0, System.Array.IndexOf(TimerChoices, seconds));
    private static int TimerSeconds(int index) => index >= 0 && index < TimerChoices.Length ? TimerChoices[index] : 0;

    private void OnAddRound(object? sender, RoutedEventArgs e)
    {
        if (RoundModeBox.SelectedItem is not GameMode mode || RoundCountBox.SelectedItem is not int count) return;
        _rounds.Add(new NightRound { Kind = mode, Count = count });
        _notes.Add(RoundNoteBox.Text?.Trim() ?? "");
        _timers.Add(0);
        RoundNoteBox.Text = "";
        RebuildBuilderRounds();
    }

    /// Move a round up (−1) or down (+1) in the running order (note travels with it).
    private void MoveRound(int index, int delta)
    {
        int target = index + delta;
        if (index < 0 || index >= _rounds.Count || target < 0 || target >= _rounds.Count) return;
        (_rounds[index], _rounds[target]) = (_rounds[target], _rounds[index]);
        (_notes[index], _notes[target]) = (_notes[target], _notes[index]);
        (_timers[index], _timers[target]) = (_timers[target], _timers[index]);
        RebuildBuilderRounds();
    }

    private void RebuildBuilderRounds()
    {
        BuilderRounds.Children.Clear();
        for (int i = 0; i < _rounds.Count; i++)
        {
            int idx = i;
            var r = _rounds[i];
            var note = idx < _notes.Count ? _notes[idx] : "";
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto,Auto"), Margin = new Avalonia.Thickness(0, 0, 0, 2) };
            var label = note.Length > 0
                ? $"{idx + 1}. {r.Kind.Title()} · {r.Count} questions  📝 {note}"
                : $"{idx + 1}. {r.Kind.Title()} · {r.Count} questions";
            row.Children.Add(new TextBlock { Text = label, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis });
            // Wave A per-round countdown (macOS parity). "No timer" is first and the
            // default: a pub quiz that silently starts a clock on every round would change
            // how the room plays without the host asking for it.
            var timer = new ComboBox
            {
                ItemsSource = new[] { "No timer", "30s", "45s", "60s", "90s", "120s" },
                SelectedIndex = TimerIndex(idx < _timers.Count ? _timers[idx] : 0),
                MinWidth = 96, FontSize = 12,
            };
            Avalonia.Automation.AutomationProperties.SetName(timer, $"Countdown for round {idx + 1}");
            timer.SelectionChanged += (_, _) =>
            {
                while (_timers.Count <= idx) _timers.Add(0);
                _timers[idx] = TimerSeconds(timer.SelectedIndex);
            };
            Grid.SetColumn(timer, 1);
            row.Children.Add(timer);

            var up = new Button { Content = "▲", Padding = new Avalonia.Thickness(7, 2), FontSize = 11, IsEnabled = idx > 0 };
            AutomationProperties.SetName(up, $"Move round {idx + 1} up");
            up.Click += (_, _) => MoveRound(idx, -1);
            Grid.SetColumn(up, 2);
            row.Children.Add(up);
            var down = new Button { Content = "▼", Padding = new Avalonia.Thickness(7, 2), FontSize = 11, IsEnabled = idx < _rounds.Count - 1, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(down, $"Move round {idx + 1} down");
            down.Click += (_, _) => MoveRound(idx, +1);
            Grid.SetColumn(down, 3);
            row.Children.Add(down);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(8, 2), FontSize = 12, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(del, $"Remove round {idx + 1}");
            del.Click += (_, _) => { _rounds.RemoveAt(idx); if (idx < _notes.Count) _notes.RemoveAt(idx); if (idx < _timers.Count) _timers.RemoveAt(idx); RebuildBuilderRounds(); };
            Grid.SetColumn(del, 4);
            row.Children.Add(del);
            BuilderRounds.Children.Add(row);
        }
        RebuildBalance();
    }

    /// The balance meter — a bar per question type (width ∝ its share) + a variety
    /// verdict, so the host can see the night's mix as they compose it.
    private void RebuildBalance()
    {
        BalancePanel.Children.Clear();
        BalancePanel.IsVisible = _rounds.Count > 0;
        if (_rounds.Count == 0) return;

        var shares = Tidbits.Core.Networking.LiveEventBalance.ByType(_rounds);
        int max = shares.Count > 0 ? System.Math.Max(1, shares.Max(s => s.Questions)) : 1;
        foreach (var s in shares)
        {
            var stack = new Panel { Height = 22, Margin = new Avalonia.Thickness(0, 1) };
            stack.Children.Add(new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#33FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(5), HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                Width = 120 + 260.0 * s.Questions / max,
            });
            stack.Children.Add(new TextBlock
            {
                Text = $"{s.Kind.Title()} · {s.Questions}", FontSize = 12, Margin = new Avalonia.Thickness(8, 0),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            BalancePanel.Children.Add(stack);
        }
        BalancePanel.Children.Add(new TextBlock
        {
            Text = Tidbits.Core.Networking.LiveEventBalance.Verdict(_rounds),
            FontSize = 12, FontWeight = Avalonia.Media.FontWeight.SemiBold, Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35")),
            Margin = new Avalonia.Thickness(0, 4, 0, 0),
        });
    }

    private LiveEvent CurrentEvent() => new()
    {
        Name = string.IsNullOrWhiteSpace(EventNameBox.Text) ? "Custom Night" : EventNameBox.Text!.Trim(),
        Rounds = new System.Collections.Generic.List<NightRound>(_rounds),
        Sponsor = string.IsNullOrWhiteSpace(SponsorBox.Text) ? null : SponsorBox.Text!.Trim(),
        BrandHex = string.IsNullOrWhiteSpace(BrandHexBox.Text) ? null : BrandHexBox.Text!.Trim(),
        LeadCaptureUrl = string.IsNullOrWhiteSpace(LeadUrlBox.Text) ? null : LeadUrlBox.Text!.Trim(),
        Weekday = WeekdayBox.SelectedIndex >= 1 ? WeekdayBox.SelectedIndex - 1 : (int?)null,
        WagerFinalRound = WagerFinalCheck.IsChecked == true,
        RoundNotes = new System.Collections.Generic.List<string>(_notes),
        RoundTimers = new System.Collections.Generic.List<int>(_timers),
    };

    private void OnHostEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        var ev = CurrentEvent();
        StartHosting(ev.ToPlan(), ev.Name, ev);
    }

    /// Play the composed event solo (no records) to vet the questions (3.13).
    private async void OnPreviewEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        var data = GameData.Shared.Value;
        var cat = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        var plan = CurrentEvent().ToPlan();
        var questions = await data.Provider.NightQuestions(plan, cat);
        if (questions.Count == 0) { StatusText.Text = "No questions available for that event."; StatusText.IsVisible = true; return; }
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, records: null); // preview → no records
        vm.Closed += () => { CockpitHost.Content = null; Setup.IsVisible = true; };
        Setup.IsVisible = false;
        StatusText.IsVisible = false;
        CockpitHost.Content = new GameView { DataContext = vm };
        engine.StartNight(plan, cat, questions);
    }

    /// The teams' blank answer sheet — printable BEFORE the night from the plan alone
    /// (round titles + counts), which is the Wi-Fi-dies contingency hosts actually want.
    private async void OnPrintAnswerSheet(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        if (ev.Rounds.Count == 0) return;
        var html = Tidbits.Core.Networking.LiveExport.AnswerSheetHtml(ev.Name, ev.Rounds);
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tidbits-answer-sheet.html");
        try
        {
            await System.IO.File.WriteAllTextAsync(path, html);
            var top = TopLevel.GetTopLevel(this);
            if (top?.Launcher is { } launcher) await launcher.LaunchUriAsync(new Uri(new Uri("file://"), path));
        }
        catch { /* best-effort */ }
    }

    private void OnSaveEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        GameData.Shared.Value.LiveEvents.Save(CurrentEvent());
        BuildSavedEvents();
    }

    private void BuildSavedEvents()
    {
        SavedEvents.Children.Clear();
        var events = GameData.Shared.Value.LiveEvents.All;
        SavedEventsHeader.IsVisible = events.Count > 0;
        foreach (var ev in events)
        {
            var e = ev;
            var row = new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
            grid.Children.Add(new StackPanel
            {
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Spacing = 1,
                Children =
                {
                    new TextBlock { Text = e.Name, FontWeight = Avalonia.Media.FontWeight.SemiBold },
                    new TextBlock
                    {
                        Text = e.IsRecurring ? $"{e.ScheduleLine(DateTime.Now)} · {e.Summary}" : e.Summary,
                        FontSize = 12, Opacity = 0.65,
                    },
                },
            });
            var host = new Button { Content = "Host", Padding = new Avalonia.Thickness(14, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            host.Classes.Add("accent");
            host.Click += (_, _) => StartHosting(e.ToPlan(), e.Name, e);
            Grid.SetColumn(host, 1);
            grid.Children.Add(host);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(10, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            AutomationProperties.SetName(del, $"Delete saved event {e.Name}");
            del.Click += (_, _) => { GameData.Shared.Value.LiveEvents.Remove(e.Id); BuildSavedEvents(); };
            Grid.SetColumn(del, 2);
            grid.Children.Add(del);
            row.Child = grid;
            SavedEvents.Children.Add(row);
        }
    }

    private async void StartHosting(NightPlan plan, string title, LiveEvent? branding = null)
    {
        var data = GameData.Shared.Value;
        var category = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        var host = new LiveNightHost(plan, category, data.Provider, title)
        {
            SpeedBonus = SpeedBonusCheck.IsChecked == true,
            HostPlays = HostPlaysCheck.IsChecked == true,
            HostName = string.IsNullOrWhiteSpace(HostNameBox.Text) ? "Host" : HostNameBox.Text!.Trim(),
            Sponsor = branding?.Sponsor,
            BrandHex = branding?.BrandHex,
            LeadCaptureUrl = branding?.LeadCaptureUrl,
            WagerRoundIndex = branding?.WagerFinalRound == true ? System.Math.Max(0, plan.Rounds.Count - 1) : null,
            RoundNotes = branding?.RoundNotes ?? new System.Collections.Generic.List<string>(),
            RoundTimers = branding?.RoundTimers ?? new System.Collections.Generic.List<int>(),
        };
        var vm = new LiveHostViewModel(host);
        Setup.IsVisible = false;
        CockpitHost.Content = new LiveCockpitView { DataContext = vm };
        StatusText.IsVisible = false;
        try
        {
            await vm.StartHosting();
            if (!host.IsOpen)
            {
                // Couldn't open a room — return to setup with the reason.
                CockpitHost.Content = null;
                Setup.IsVisible = true;
                StatusText.Text = host.ErrorText ?? "Couldn't start hosting.";
                StatusText.IsVisible = true;
            }
        }
        catch (Exception ex)
        {
            CockpitHost.Content = null;
            Setup.IsVisible = true;
            StatusText.Text = $"Couldn't start hosting: {ex.Message}";
            StatusText.IsVisible = true;
        }
    }

    private void OnJoinGame(object? sender, RoutedEventArgs e) => JoinAsPlayer(null, null);

    /// Open the player-join surface, optionally pre-filled and auto-submitted.
    ///
    /// `code == null` is the ordinary button path: show the form and let the player
    /// type. With a code, the harness path fills both fields and joins — the same
    /// code path a person drives, not a parallel one, so what it proves is what a
    /// person would get.
    private void JoinAsPlayer(string? code, string? name)
    {
        Setup.IsVisible = false;
        var view = new JoinPlayerView { DataContext = new LivePlayerViewModel() };
        CockpitHost.Content = view;
        if (code is not null) view.AutoJoin(code, name);
    }

    /// Called by the cockpit's Close to return to setup.
    public void BackToSetup()
    {
        CockpitHost.Content = null;
        Setup.IsVisible = true;
    }
}
