using System;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.VisualTree;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class LiveCockpitView : UserControl
{
    private string _qrCode = "";

    private readonly Avalonia.Threading.DispatcherTimer _tick;

    public LiveCockpitView()
    {
        InitializeComponent();
        AttachedToVisualTree += (_, _) =>
            Avalonia.Threading.Dispatcher.UIThread.Post(OpenProjectorFromHook, Avalonia.Threading.DispatcherPriority.Background);
            Avalonia.Threading.Dispatcher.UIThread.Post(RunScriptHooks, Avalonia.Threading.DispatcherPriority.Background);
        // Tick the countdown display once a second (the deadline itself lives in the
        // published pub; this just renders the remaining seconds locally).
        _tick = new Avalonia.Threading.DispatcherTimer(
            TimeSpan.FromSeconds(1), Avalonia.Threading.DispatcherPriority.Normal, (_, _) => RefreshCountdown());
        _tick.Start();
        DetachedFromVisualTree += (_, _) => _tick.Stop();
        // Keyboard cockpit — tunnel so the show keys beat button focus.
        AddHandler(KeyDownEvent, OnCockpitKey, Avalonia.Interactivity.RoutingStrategies.Tunnel);
    }

    private async void OnCockpitKey(object? sender, Avalonia.Input.KeyEventArgs e)
    {
        if (Vm is not { } vm) return;
        var action = Services.CockpitKeymap.Resolve(e.Key, vm.Host.Revealed);
        if (action == Services.CockpitAction.None) return;
        e.Handled = true;
        switch (action)
        {
            case Services.CockpitAction.Reveal: await vm.Reveal(); break;
            case Services.CockpitAction.Next: await vm.Next(); break;
            case Services.CockpitAction.Back: await vm.Back(); break;
            case Services.CockpitAction.Skip: await vm.Skip(); break;
            case Services.CockpitAction.Lock: await vm.Lock(); break;
        }
    }

    private void RefreshCountdown()
    {
        if (Vm is not { } vm) { CountdownText.Text = ""; return; }
        var s = vm.SecondsRemaining;
        CountdownText.Text = s is { } n ? $"{n}s" : "";
        // Auto-lock at pencils-down: when the deadline hits 0, lock the round
        // (idempotent — Host.Lock no-ops once locked/revealed).
        if (vm.AutoLockDue) _ = vm.Lock();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (DataContext is LiveHostViewModel pvm) pvm.PropertyChanged += (_, _) => RefreshCockpitPicture();
        RefreshCockpitPicture();
        if (Vm is { } vm) vm.PropertyChanged += (_, _) => { RefreshQr(); RefreshTally(); RefreshReview(); };
        RefreshQr();
        RefreshTally();
        RefreshReview();
    }

    /// On reveal of a Name-It round, list each team's typed answer with an
    /// auto-verdict; an "Accept" button awards a borderline spelling.
    private void RefreshReview()
    {
        ReviewPanel.Children.Clear();
        var rows = Vm?.TextReview;
        if (rows is null || rows.Count == 0) return;

        ReviewPanel.Children.Add(new TextBlock { Text = "Free-text review", FontWeight = FontWeight.Bold, FontSize = 14 });
        foreach (var r in rows)
        {
            var row = r;
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto"), Margin = new Avalonia.Thickness(0, 2, 0, 0) };
            grid.Children.Add(new TextBlock
            {
                Text = $"{row.Name}: “{row.Text}”", TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                Opacity = row.AutoCorrect ? 1 : 0.75,
            });
            var credited = row.AutoCorrect || row.Accepted;
            var verdict = new TextBlock
            {
                Text = credited ? "✓" : "✗", FontWeight = FontWeight.Black,
                Foreground = new SolidColorBrush(Color.Parse(credited ? "#1E9E6A" : "#D64545")),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Margin = new Avalonia.Thickness(8, 0),
            };
            Grid.SetColumn(verdict, 1);
            grid.Children.Add(verdict);
            if (row.Accepted)
            {
                var done = new TextBlock { Text = "Accepted", FontSize = 12, Opacity = 0.7, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center };
                Grid.SetColumn(done, 2);
                grid.Children.Add(done);
            }
            else if (!row.AutoCorrect)
            {
                var accept = new Button { Content = "Accept", Padding = new Avalonia.Thickness(10, 3), FontSize = 12, Tag = row.Uid };
                Avalonia.Automation.AutomationProperties.SetName(accept, $"Accept {row.Name}");
                accept.Click += OnAcceptText;
                Grid.SetColumn(accept, 2);
                grid.Children.Add(accept);
                // 3.21: the same ruling for every team that typed this — the answer
                // joins the question's accepted list, so the rows turn ✓ together.
                var all = new Button
                {
                    Content = "Accept from everyone", Padding = new Avalonia.Thickness(10, 3), FontSize = 12, Tag = row.Text,
                    Margin = new Avalonia.Thickness(4, 0, 0, 0),
                };
                ToolTip.SetTip(all, $"Rule “{row.Text}” correct for every team that typed it, and for the rest of the night");
                Avalonia.Automation.AutomationProperties.SetName(all, $"Accept {row.Text} from everyone");
                all.Click += OnAcceptTextForAll;
                Grid.SetColumn(all, 3);
                grid.Children.Add(all);
            }
            ReviewPanel.Children.Add(grid);
        }
    }

    private async void OnAcceptText(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            await vm.AcceptText(uid);
    }

    private async void OnAcceptTextForAll(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string text && text.Trim().Length > 0)
            await vm.AcceptTextForAll(text);
    }

    /// 3.55: fix the question on screen without leaving the night — the same
    /// editor as the builder; the room and the projector get the change at once.
    private async void OnEditQuestion(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || vm.Host.Current is not { } q || vm.ShowBoardScreen) return;
        string? newClip = null; bool clipChanged = false; string? newNote = null;
        var updated = await LiveQuestionEditorDialog.ShowAsync(q, vm.Host.CurrentKind, "Edit this question",
            vm.CurrentClipPath, path => { newClip = path; clipChanged = true; },
            vm.Host.CurrentQuestionNote, n => newNote = n);
        if (updated is null) return;
        if (newNote is not null) vm.Host.SetCurrentNote(newNote);
        await vm.Host.ReplaceCurrent(updated);
        if (clipChanged) await vm.Host.SetCurrentClip(newClip);
    }

    /// Rebuild the options with a live per-option answer-distribution bar. The
    /// correct option is tinted green on reveal.
    /// The tally column's measured width, so a vote fills a real proportion of the
    /// row rather than a guessed 500px. NaN until the panel has been laid out once.
    private double TallyWidth => OptionsTally?.Bounds.Width ?? double.NaN;

    private void RefreshTally()
    {
        OptionsTally.Children.Clear();
        var host = Vm?.Host;
        if (host?.Current is not { } q || q.Options.Count == 0 || !Tidbits.Core.Networking.LiveScoring.IsMcq(q)) return;   // a Name-It's `options` is its accepted list, not a ballot
        // G5: while the pick-a-category grid is up the room has not chosen a cell,
        // so there is no live question — and these bars were still listing the
        // OPTIONS of the one the host happens to be sitting on. A host reading
        // four answers to a question nobody asked is the same confusion the
        // hidden Reveal button caused.
        if (Vm is { ShowBoardScreen: true }) return;

        var dist = host.AnswerDistribution;
        int max = dist.Count > 0 ? Math.Max(1, dist.Max()) : 1;
        bool reveal = host.Revealed;

        // Row height by option COUNT, not a fixed 34. A four-option question left
        // ~170px of dead space between the last answer and the controls on a real
        // 1080-wide window; a taller row fills it AND is easier to read across a
        // room, which is the whole job of this panel. Deterministic rather than
        // measured — a height that depends on a laid-out viewport changes between
        // the first and second layout pass and makes the capture non-reproducible.
        double rowH = q.Options.Count <= 4 ? 64 : q.Options.Count <= 6 ? 52 : 42;

        for (int i = 0; i < q.Options.Count; i++)
        {
            int count = i < dist.Count ? dist[i] : 0;
            bool correct = reveal && i == q.CorrectIndex;

            // A full-width TRACK with the vote filling it, not a pill sized to the
            // vote. At zero votes the old bar collapsed to its 60px MinWidth, so the
            // panel had no presence and the body row's slack showed as a void in
            // the middle of the cockpit — visible on the real box at 1080 wide.
            // A track also shows the SCALE: a host can see 3-of-10 as a third of a
            // row rather than having to read the number.
            var track = new Border
            {
                Height = rowH, CornerRadius = new Avalonia.CornerRadius(8),
                Background = new Avalonia.Media.SolidColorBrush(
                    Avalonia.Media.Color.Parse("#0F808080")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
            };
            var fill = new Border
            {
                Height = rowH, CornerRadius = new Avalonia.CornerRadius(8),
                Background = new Avalonia.Media.SolidColorBrush(
                    Avalonia.Media.Color.Parse(correct ? "#3320A060" : "#22808080")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                // A zero-vote row still shows a sliver, so the row reads as a bar at
                // 0 rather than as an empty box.
                Width = 6 + (double.IsNaN(TallyWidth) ? 460 : TallyWidth - 6) * count / max,
            };
            var label = new TextBlock
            {
                Text = q.Options[i], VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                Margin = new Avalonia.Thickness(12, 0), FontWeight = correct ? Avalonia.Media.FontWeight.Bold : Avalonia.Media.FontWeight.Normal,
            };
            var countTb = new TextBlock
            {
                Text = count.ToString(), FontWeight = Avalonia.Media.FontWeight.Bold, Opacity = count > 0 ? 0.9 : 0.4,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Margin = new Avalonia.Thickness(8, 0),
            };
            var over = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            over.Children.Add(label);
            Grid.SetColumn(countTb, 1);
            over.Children.Add(countTb);
            var stack = new Panel();          // the fill sits behind the label + count
            stack.Children.Add(track);
            stack.Children.Add(fill);
            stack.Children.Add(over);
            OptionsTally.Children.Add(stack);
        }
    }

    /// Generate the join QR once the room code is known (and only when it changes).
    private void RefreshQr()
    {
        var code = Vm?.Host.Code ?? "";
        if (code.Length == 0 || code == _qrCode) return;
        _qrCode = code;
        try { QrImage.Source = QrHelper.Generate(QrHelper.JoinUrl(code)); } catch { }
    }

    private LiveHostViewModel? Vm => DataContext as LiveHostViewModel;

    /// WINDOWS-DESIGN §6.2 — the menu bar drives the SAME handlers the buttons do,
    /// so a command can never exist in one place and not the other. One dispatcher
    /// rather than a dozen public wrappers.
    public void RunCommand(string id)
    {
        var e = new RoutedEventArgs();
        switch (id)
        {
            case "reveal":     OnReveal(this, e); break;
            case "next":       OnNext(this, e); break;
            case "previous":   OnBack(this, e); break;
            case "lock":       OnLock(this, e); break;
            case "skip":       OnSkip(this, e); break;
            case "add30":      OnAdd30(this, e); break;
            case "add15":      OnAdd15(this, e); break;
            case "clearTimer": OnClearTimer(this, e); break;
            case "hold":       OnToggleHold(this, e); break;
            case "projector":  OnProjector(this, e); break;
            case "endNight":   OnClose(this, e); break;
        }
    }

    private async void OnReveal(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Reveal(); }
    private async void OnNext(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Next(); }
    private async void OnLock(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Lock(); }
    private async void OnSkip(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Skip(); }
    private void OnToggleHold(object? sender, RoutedEventArgs e) => Vm?.ToggleHold();

    /// A3.14: hold the show for an interval. Distinct from the standings hold — this one
    /// tells the room, not just the big screen.
    private async void OnToggleBreak(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm) await vm.ToggleBreak();
    }

    /// A break with a stated return time is what a host writes on a board; here every
    /// phone counts it down too.
    private async void OnBreakFor(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        var picker = new ComboBox
        {
            ItemsSource = Tidbits.Core.Networking.LiveBreak.Choices.Select(m => $"{m} minutes").ToList(),
            SelectedIndex = 1, MinWidth = 200,
        };
        Avalonia.Automation.AutomationProperties.SetName(picker, "How long is the break");
        var dlg = new FAContentDialog
        {
            Title = "Break with a return time",
            Content = picker,
            PrimaryButtonText = "Start the break",
            CloseButtonText = "Cancel",
        };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary)
            await vm.BreakFor(Tidbits.Core.Networking.LiveBreak.Choices[Math.Max(0, picker.SelectedIndex)]);
    }
    private void OnToggleRemote(object? sender, RoutedEventArgs e) => Vm?.ToggleRemote();

    /// G5: the host taps the cell the room called out.
    private async void OnPickBoardCell(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        if ((sender as Control)?.DataContext is not LiveHostViewModel.BoardTile tile) return;
        await vm.PickBoardCell(tile.CategoryId, tile.Tier);
    }

    private int _bedVolume = 60;
    private bool _bedPlaying;
    private string? _outputDevice;

    private static readonly Avalonia.Platform.Storage.FilePickerFileType AudioFilter =
        new("Audio") { Patterns = new[] { "*.mp3", "*.wav", "*.m4a", "*.ogg", "*.aac", "*.flac" } };

    private async System.Threading.Tasks.Task<string?> PickAudio(string title, bool multiple, System.Action<string> each)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top is null) return null;
        var files = await top.StorageProvider.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = title, AllowMultiple = multiple, FileTypeFilter = new[] { AudioFilter },
        });
        string? last = null;
        foreach (var f in files) { each(f.Path.LocalPath); last = f.Path.LocalPath; }
        return last;
    }

    /// The host audio center (Wave B): PA output routing (3.31), a looping music bed
    /// (3.33), and the SFX board (3.30), all through the shared AvPlayer.
    private async void OnAudio(object? sender, RoutedEventArgs e)
    {
        var g = Services.GameData.Shared.Value;
        var dialog = new FAContentDialog { Title = "Audio", CloseButtonText = "Done" };

        void Rebuild() => dialog.Content = AudioPanelUi.BuildPanel(
            devices: g.Av.OutputDevices(), currentDevice: _outputDevice,
            onDevice: id => { _outputDevice = id; g.Av.SetOutputDevice(id); },
            bedPlaying: _bedPlaying, bedVolume: _bedVolume,
            onChooseBed: async () =>
            {
                var picked = await PickAudio("Choose a music bed", false, _ => { });
                if (picked is not null) { g.Av.PlayBed(picked); g.Av.SetBedVolume(_bedVolume); _bedPlaying = true; Rebuild(); }
            },
            onStopBed: () => { g.Av.StopBed(); _bedPlaying = false; Rebuild(); },
            onBedVolume: v => { _bedVolume = v; g.Av.SetBedVolume(v); },
            pads: g.Sfx.Pads,
            onPlaySfx: path => g.Av.PlaySfx(path),
            onAddSfx: async () => { await PickAudio("Add a sound", true, p => g.Sfx.Add(p)); Rebuild(); },
            onRemoveSfx: path => { g.Sfx.Remove(path); Rebuild(); },
            // Audio round (3.32): play a clip for the current question, in the room.
            onPlayAudioClip: async () => { var p = await PickAudio("Play an audio clip", false, _ => { }); if (p is not null) g.Av.PlayClip(p); },
            onStopClip: () => g.Av.StopClip(),
            onPauseClip: () => g.Av.PauseClip());

        Rebuild();
        await dialog.ShowAsync();
    }
    private async void OnBack(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Back(); }

    private async void OnTimer30(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.StartTimer(30); RefreshCountdown(); }
    private async void OnTimer60(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.StartTimer(60); RefreshCountdown(); }
    private async void OnAdd15(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.AddTime(15); RefreshCountdown(); }
    private async void OnAdd30(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.AddTime(30); RefreshCountdown(); }
    private async void OnClearTimer(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.ClearTimer(); RefreshCountdown(); }

    /// Merge teams — pick the team to keep and the team to fold into it (their
    /// scores combine; the folded team leaves the big screen).
    private async void OnMergeTeams(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || vm.Host.Standings.Count < 2) return;
        var teams = new System.Collections.Generic.List<Tidbits.Core.Networking.LiveHostNet.Joined>(vm.Host.Standings);
        var tmpl = new Avalonia.Controls.Templates.FuncDataTemplate<Tidbits.Core.Networking.LiveHostNet.Joined>(
            (t, _) => new TextBlock { Text = $"{t.Name} ({t.Score})" });
        var keep = new ComboBox { ItemsSource = teams, ItemTemplate = tmpl, SelectedIndex = 0, MinWidth = 240 };
        var fold = new ComboBox { ItemsSource = teams, ItemTemplate = tmpl, SelectedIndex = 1, MinWidth = 240 };

        var panel = new StackPanel { Spacing = 8, MinWidth = 300 };
        panel.Children.Add(new TextBlock { Text = "Fold the second team into the first — their scores combine.", TextWrapping = Avalonia.Media.TextWrapping.Wrap, Opacity = 0.75 });
        panel.Children.Add(new TextBlock { Text = "Keep", FontWeight = FontWeight.SemiBold, Margin = new Avalonia.Thickness(0, 6, 0, 0) });
        panel.Children.Add(keep);
        panel.Children.Add(new TextBlock { Text = "Fold in", FontWeight = FontWeight.SemiBold, Margin = new Avalonia.Thickness(0, 6, 0, 0) });
        panel.Children.Add(fold);

        var dlg = new FAContentDialog { Title = "Merge teams", Content = panel, PrimaryButtonText = "Merge", CloseButtonText = "Cancel" };
        var result = await dlg.ShowAsync();
        if (result == FAContentDialogResult.Primary
            && keep.SelectedItem is Tidbits.Core.Networking.LiveHostNet.Joined a
            && fold.SelectedItem is Tidbits.Core.Networking.LiveHostNet.Joined b)
            await vm.MergeTeams(a.Id, b.Id);
    }

    /// Tie-break — pick the winner among the teams tied for first (+1 to them).
    private async void OnBreakTie(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || !vm.HasTie) return;
        var tied = new System.Collections.Generic.List<Tidbits.Core.Networking.LiveHostNet.Joined>(vm.TiedLeaders);
        var pick = new ComboBox
        {
            ItemsSource = tied, SelectedIndex = 0, MinWidth = 240,
            ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<Tidbits.Core.Networking.LiveHostNet.Joined>(
                (t, _) => new TextBlock { Text = $"{t.Name} ({t.Score})" }),
        };
        // 3.58 (A3.5): the numeric engine the Mac has — a nearest-wins number
        // question, each tied team's guess typed in, the closest takes +1.
        var mode = new ComboBox { ItemsSource = new[] { "Closest number", "Brains-only" }, SelectedIndex = 0, MinWidth = 240 };
        Avalonia.Automation.AutomationProperties.SetName(mode, "Tie-break method");
        var target = new TextBox { Watermark = "e.g. 1889", MinWidth = 120 };
        Avalonia.Automation.AutomationProperties.SetName(target, "Correct number");
        var guesses = new System.Collections.Generic.Dictionary<string, TextBox>();
        var numeric = new StackPanel { Spacing = 6 };
        numeric.Children.Add(new TextBlock
        {
            Text = "Ask a number question (e.g. \u201cwhat year did the Eiffel Tower open?\u201d). Enter the answer, then each team's guess — closest wins +1.",
            TextWrapping = TextWrapping.Wrap, Opacity = 0.75,
        });
        var targetRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        targetRow.Children.Add(new TextBlock { Text = "Correct number", FontWeight = FontWeight.SemiBold, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center });
        Grid.SetColumn(target, 1); targetRow.Children.Add(target);
        numeric.Children.Add(targetRow);
        foreach (var t in tied)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            row.Children.Add(new TextBlock { Text = t.Name, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
            var g = new TextBox { Watermark = "guess", MinWidth = 120 };
            Avalonia.Automation.AutomationProperties.SetName(g, $"Guess by {t.Name}");
            Grid.SetColumn(g, 1); row.Children.Add(g);
            guesses[t.Id] = g;
            numeric.Children.Add(row);
        }
        var brains = new StackPanel { Spacing = 8, IsVisible = false };
        brains.Children.Add(new TextBlock { Text = "Phones down. Ask a question aloud — first correct hand wins. Pick the team that won; they get +1 to take the lead.", TextWrapping = TextWrapping.Wrap, Opacity = 0.75 });
        brains.Children.Add(pick);
        mode.SelectionChanged += (_, _) => { numeric.IsVisible = mode.SelectedIndex == 0; brains.IsVisible = mode.SelectedIndex == 1; };

        var panel = new StackPanel { Spacing = 10, MinWidth = 340 };
        panel.Children.Add(mode);
        panel.Children.Add(numeric);
        panel.Children.Add(brains);
        var dlg = new FAContentDialog { Title = "Break the tie", Content = panel, PrimaryButtonText = "Resolve tie", CloseButtonText = "Cancel" };
        if (await dlg.ShowAsync() != FAContentDialogResult.Primary) return;
        if (mode.SelectedIndex == 1)
        {
            if (pick.SelectedItem is Tidbits.Core.Networking.LiveHostNet.Joined w) await vm.BreakTie(w.Id);
            return;
        }
        if (!double.TryParse(target.Text, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var answer)) return;
        var typed = new System.Collections.Generic.Dictionary<string, double>();
        foreach (var (uid, box) in guesses)
            if (double.TryParse(box.Text, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v)) typed[uid] = v;
        await vm.BreakTieClosest(answer, typed);
    }

    /// Drop a team from the night (macOS parity — the per-team "Remove team"). Destructive and
    /// mid-night, so it names the team in the confirm and defaults to Cancel.
    private async void OnRemoveTeam(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || vm.Host.Standings.Count == 0) return;
        var teams = new System.Collections.Generic.List<Tidbits.Core.Networking.LiveHostNet.Joined>(vm.Host.Standings);
        var pick = new ComboBox
        {
            ItemsSource = teams, SelectedIndex = 0, MinWidth = 260,
            ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<Tidbits.Core.Networking.LiveHostNet.Joined>(
                (t, _) => new TextBlock { Text = $"{t.Name} ({t.Score})" }),
        };
        var panel = new StackPanel { Spacing = 8, MinWidth = 300 };
        panel.Children.Add(new TextBlock
        {
            Text = "Removes the team from the standings, the big screen and the export. "
                 + "Their phone stays connected — this un-scores them, it doesn't kick them.",
            TextWrapping = TextWrapping.Wrap, Opacity = 0.75,
        });
        panel.Children.Add(pick);
        var dlg = new FAContentDialog
        {
            Title = "Remove a team", Content = panel,
            PrimaryButtonText = "Remove team", CloseButtonText = "Cancel",
            DefaultButton = FAContentDialogButton.Close,
        };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary
            && pick.SelectedItem is Tidbits.Core.Networking.LiveHostNet.Joined t)
            await vm.RemoveTeam(t.Id);
    }

    /// Add an in-room paper team to the standings (host scores it with −/+).
    private async void OnAddPaperTeam(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        var box = new TextBox { Watermark = "Team name", MinWidth = 260 };
        var dlg = new FAContentDialog
        {
            Title = "Add a paper team", Content = box, PrimaryButtonText = "Add", CloseButtonText = "Cancel",
        };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary && !string.IsNullOrWhiteSpace(box.Text))
            vm.AddPaperTeam(box.Text);
    }

    // Name moderation gate — toggle a team's name off the big screen.
    /// A2.14: a paper table has no phone — the host plays its joker. Each click moves
    /// to the next round still ahead, then clears it.
    private void OnCycleJoker(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            vm.CycleJoker(uid);
    }

    private void OnToggleHide(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            vm.ToggleHidden(uid);
    }

    // Manual score override — the team uid rides the button's Tag.
    private async void OnScoreUp(object? sender, RoutedEventArgs e) => await Adjust(sender, +1);
    private async void OnScoreDown(object? sender, RoutedEventArgs e) => await Adjust(sender, -1);

    private async System.Threading.Tasks.Task Adjust(object? sender, int delta)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            await vm.Adjust(uid, delta);
    }

    /// Export the unified standings to a CSV file via the native save picker.
    private async void OnExportCsv(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || !vm.HasStandings) return;
        var top = TopLevel.GetTopLevel(this);
        if (top is null) return;
        var file = await top.StorageProvider.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
        {
            Title = "Export standings",
            SuggestedFileName = $"tidbits-standings-{vm.Host.Code}.csv",
            DefaultExtension = "csv",
            FileTypeChoices = new[]
            {
                new Avalonia.Platform.Storage.FilePickerFileType("CSV") { Patterns = new[] { "*.csv" } },
            },
        });
        if (file is null) return;
        await using var stream = await file.OpenWriteAsync();
        await using var writer = new System.IO.StreamWriter(stream);
        await writer.WriteAsync(vm.StandingsCsv());
    }

    /// A3.12: a typo on the big screen, fixed by the host for the whole night.
    private async void OnRenameTeam(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || (sender as Control)?.Tag is not string uid || uid.Length == 0) return;
        var current = vm.Host.Standings.Where(j => j.Id == uid).Select(j => j.Name).FirstOrDefault() ?? "";
        var box = new TextBox { Text = current, Watermark = "Team name", MinWidth = 260 };
        Avalonia.Automation.AutomationProperties.SetName(box, "New team name");
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(box);
        panel.Children.Add(new TextBlock { Text = "The new name shows on the big screen, the standings and the exports for the rest of the night. The table's phone keeps what it typed.", Opacity = 0.7, TextWrapping = TextWrapping.Wrap, MaxWidth = 340 });
        var dlg = new FAContentDialog { Title = "Rename team", Content = panel, PrimaryButtonText = "Rename", CloseButtonText = "Cancel" };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary && !string.IsNullOrWhiteSpace(box.Text)) await vm.RenameTeam(uid, box.Text);
    }

    /// A3.11 / 3.68: the night read back — the same numbers the Mac's final standings show.
    private async void OnNightReport(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        var r = vm.Report;
        var panel = new StackPanel { Spacing = 8, MinWidth = 380 };
        if (r.IsEmpty)
        {
            panel.Children.Add(new TextBlock { Text = "Nothing to read back yet — reveal a question first.", Opacity = 0.75, TextWrapping = TextWrapping.Wrap });
        }
        else
        {
            var stats = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*,*") };
            void Stat(int col, string value, string label)
            {
                var b = new StackPanel { Spacing = 2, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center };
                b.Children.Add(new TextBlock { Text = value, FontSize = 22, FontWeight = FontWeight.Black, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center });
                b.Children.Add(new TextBlock { Text = label, FontSize = 12, Opacity = 0.7, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center });
                Grid.SetColumn(b, col); stats.Children.Add(b);
            }
            Stat(0, Tidbits.Core.Networking.LiveNightReport.Percent(r.OverallAccuracy), "answers right");
            Stat(1, Tidbits.Core.Networking.LiveNightReport.Percent(r.Participation), "tables answering");
            Stat(2, r.Questions.Count.ToString(), "questions");
            panel.Children.Add(stats);
            void Q(string label, Tidbits.Core.Networking.LiveNightReport.QuestionStat q, string color)
            {
                panel.Children.Add(new TextBlock { Text = $"{label.ToUpperInvariant()} · {Tidbits.Core.Networking.LiveNightReport.Percent(q.Accuracy)} of {q.Answered} got it", FontSize = 12, FontWeight = FontWeight.Bold, Foreground = new SolidColorBrush(Color.Parse(color)) });
                panel.Children.Add(new TextBlock { Text = q.Prompt, TextWrapping = TextWrapping.Wrap });
                panel.Children.Add(new TextBlock { Text = "Answer: " + q.Answer, FontSize = 12, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
            }
            if (r.Hardest is { } h) Q("Hardest", h, "#D64545");
            if (r.Easiest is { } ez && ez.Qid != r.Hardest?.Qid) Q("Easiest", ez, "#1E9E6A");
            if (r.Rounds.Count > 1)
            {
                var rounds = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
                foreach (var rs in r.Rounds)
                    rounds.Children.Add(new Border { CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(10, 4), Background = new SolidColorBrush(Color.Parse("#1F808080")),
                        Child = new TextBlock { Text = $"Round {rs.Round} · {Tidbits.Core.Networking.LiveNightReport.Percent(rs.Accuracy)}", FontSize = 12 } });
                panel.Children.Add(rounds);
            }
        }
        var dlg = new FAContentDialog { Title = "How the night went", Content = panel, PrimaryButtonText = r.IsEmpty ? null : "Print with the standings", CloseButtonText = "Close" };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary) OnPrintStandings(this, e);
    }

    /// A3.8 / 3.62: the answer sheet — every team's submission and credit per question.
    private async void OnExportAnswers(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || !vm.HasAnswerLog) return;
        var top = TopLevel.GetTopLevel(this);
        if (top is null) return;
        var file = await top.StorageProvider.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
        {
            Title = "Export answer sheet",
            SuggestedFileName = $"tidbits-answers-{vm.Host.Code}.csv",
            DefaultExtension = "csv",
            FileTypeChoices = new[] { new Avalonia.Platform.Storage.FilePickerFileType("CSV") { Patterns = new[] { "*.csv" } } },
        });
        if (file is null) return;
        await using var stream = await file.OpenWriteAsync();
        await using var writer = new System.IO.StreamWriter(stream);
        await writer.WriteAsync(vm.AnswersCsv());
    }

    /// The host's question pack for the night IN PROGRESS — printed from the cockpit rather
    /// than the builder because a saved event stores only {kind, count}: a pack drawn at build
    /// time would list different questions than the room is actually being asked.
    private async void OnPrintPack(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || vm.Host.Questions.Count == 0) return;
        var html = Tidbits.Core.Networking.LiveExport.QuestionPackHtml(vm.Host.Title, vm.Host.Questions);
        await OpenPrintable(html, $"tidbits-pack-{vm.Host.Code}.html");
    }

    /// Write a print-ready page to temp and hand it to the default browser, which is where
    /// Windows users print or save-as-PDF from.
    private async System.Threading.Tasks.Task OpenPrintable(string html, string fileName)
    {
        try
        {
            var path = Tidbits.Core.Networking.LiveExport.WritePrintable(html, fileName);
            var top = TopLevel.GetTopLevel(this);
            if (top?.Launcher is { } launcher) await launcher.LaunchUriAsync(new Uri(new Uri("file://"), path));
        }
        catch { /* best-effort */ }
    }

    /// Print standings — write a print-ready HTML sheet and open it in the default
    /// browser (which prints / saves to PDF). The $0 printable fallback.
    private async void OnPrintStandings(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm || !vm.HasStandings) return;
        var html = Tidbits.Core.Networking.LiveExport.StandingsHtml(vm.Host.Standings, $"{vm.Host.Title} — Standings", vm.Report);   // A3.11: the printed results carry the night report
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"tidbits-standings-{vm.Host.Code}.html");
        try
        {
            await System.IO.File.WriteAllTextAsync(path, html);
            var top = TopLevel.GetTopLevel(this);
            if (top?.Launcher is { } launcher) await launcher.LaunchUriAsync(new Uri(new Uri("file://"), path));
        }
        catch { /* best-effort */ }
    }

    /// Play the clip attached to the question on screen. Audio goes to the room
    /// through the routed PA output; a video clip is what the projector shows.
    ///
    /// This is the leg that made the round real: Windows could already play a clip
    /// the host picked ad hoc, but nothing connected an AUTHORED round's clip to
    /// the question it belongs to.
    private async void OnPlayQuestionClip(object? sender, RoutedEventArgs e)
    {
        if (Vm?.CurrentClipPath is not { } path) return;
        Services.GameData.Shared.Value.Av.PlayClip(path);
        await Vm.CueMedia();   // Decision 060: cue the phones
        await Task.Delay(600); Vm.RefreshBed();   // LibVLC reports Playing a beat later
    }

    private void OnStopQuestionClip(object? sender, RoutedEventArgs e)
    {
        Services.GameData.Shared.Value.Av.StopClip();
        Vm?.RefreshBed();
    }

    private ProjectorWindow? _projector;

    private void OnProjector(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        if (_projector is not null) { _projector.Activate(); return; }
        _projector = new ProjectorWindow(vm);
        _projector.Closed += (_, _) => _projector = null;
        _projector.Show();
    }

    /// A8.7 / A8.10: what the room sees. Each element of the live slide is a check
    /// item (the question and its answer are not on the list), then full screen —
    /// on the display the projector is on, or on any attached display by name.
    private void OnScreenMenu(object? sender, RoutedEventArgs e)
    {
        var elements = Tidbits.Core.Store.ProjectorElements.Shared;
        var menu = new MenuFlyout();
        foreach (var el in Tidbits.Core.Store.ProjectorElements.All)
        {
            var item = new MenuItem { Header = el.Title, ToggleType = MenuItemToggleType.CheckBox, IsChecked = elements.Shows(el.Id) };
            var id = el.Id;
            item.Click += (_, _) => elements.Set(id, !elements.Shows(id));
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        var all = new MenuItem { Header = "Show everything", IsEnabled = elements.HiddenCount > 0 };
        all.Click += (_, _) => elements.ShowEverything();
        menu.Items.Add(all);
        menu.Items.Add(new Separator());
        var full = new MenuItem { Header = _projector?.IsFullScreen == true ? "Exit full screen" : "Full screen" };
        full.Click += (_, _) => { EnsureProjector(); _projector?.ToggleFullScreen(); };
        menu.Items.Add(full);
        var screens = (TopLevel.GetTopLevel(this) as Window)?.Screens?.All;
        if (screens is not null)
            foreach (var sc in screens)
            {
                var target = sc;
                var item = new MenuItem { Header = $"Full screen on {sc.DisplayName ?? "display"}{(sc.IsPrimary ? " (primary)" : "")}" };
                item.Click += (_, _) => { EnsureProjector(); _projector?.FullScreenOn(target); };
                menu.Items.Add(item);
            }
        menu.ShowAt(ScreenButton);
    }

    /// 3.36 (cockpit half): the question's picture through the shared ImageCache.
    private string _cockpitPictureUrl = "";
    private void RefreshCockpitPicture()
    {
        var url = Vm?.PictureUrl ?? "";
        if (url == _cockpitPictureUrl) return;
        _cockpitPictureUrl = url;
        CockpitPicture.Source = null; CockpitPictureHint.IsVisible = true; CockpitPictureHint.Text = "Loading picture";
        if (url.Length == 0) return;
        if (Services.ImageCache.Shared.Cached(url) is { } cached) { CockpitPicture.Source = cached; CockpitPictureHint.IsVisible = false; return; }
        Services.ImageCache.Shared.LoadAsync(url).ContinueWith(t =>
            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
            {
                if (_cockpitPictureUrl != url) return;
                if (t.Status == System.Threading.Tasks.TaskStatus.RanToCompletion && t.Result is { } bmp) { CockpitPicture.Source = bmp; CockpitPictureHint.IsVisible = false; }
                else CockpitPictureHint.Text = "Picture unavailable";
            }));
    }

    /// TIDBITS_LIVE_EDIT / TIDBITS_LIVE_ACCEPT_ALL: the harness drives the two
    /// mid-night rulings through the SAME host calls as the buttons.
    private async void RunScriptHooks()
    {
        if (_scriptHooksRan) return;
        _scriptHooksRan = true;
        try
        {
            if (Services.LaunchHooks.LiveBed is { Length: > 0 } bed)
            {
                await Task.Delay(1000);
                Services.GameData.Shared.Value.Av.PlayBed(bed); Services.GameData.Shared.Value.Av.SetBedVolume(35);
            }
            if (Services.LaunchHooks.LivePlayClipAt is { } clipAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(clipAt));
                Services.LaunchHooks.Diag($"playclip hook: path={Vm?.CurrentClipPath ?? "(none)"}");
                OnPlayQuestionClip(this, new RoutedEventArgs());
                await Task.Delay(1500); Vm?.RefreshBed();
            }
            if (Services.LaunchHooks.LiveNextAt is { } nextAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(nextAt));
                if (Vm is { } v) { if (!v.Host.Revealed) { await v.Reveal(); await Task.Delay(2000); } await v.Next(); }
            }
            if (Services.LaunchHooks.LiveBreak is { } breakMins)
            {
                await Task.Delay(TimeSpan.FromSeconds(Services.LaunchHooks.LiveBreakAt));
                if (Vm is { } bv)
                {
                    if (breakMins > 0) await bv.BreakFor(breakMins); else await bv.ToggleBreak();
                    Services.LaunchHooks.Diag($"break hook: onBreak={bv.IsOnBreak} headline={bv.BreakHeadline}");
                }
            }
            if (Services.LaunchHooks.LiveFinishAt is { } finishAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(finishAt));
                if (Vm is { } fnv)
                {
                    if (!fnv.Host.Revealed) { await fnv.Reveal(); await Task.Delay(2000); }
                    await fnv.Host.End();
                    Services.LaunchHooks.Diag($"finish hook: archived={Tidbits.Core.Store.NightArchive.Shared.Value.Nights.Count}");
                }
            }
            if (Services.LaunchHooks.LiveEdit is { Length: > 0 } text)
            {
                await Task.Delay(TimeSpan.FromSeconds(Services.LaunchHooks.LiveEditAt));
                if (Vm?.Host.Current is { } q) await Vm.Host.ReplaceCurrent(q with { Prompt = text });
            }
            if (Services.LaunchHooks.LiveFixKey is { Length: > 0 } fixKey && Services.LaunchHooks.LiveFixAt is { } fixAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(fixAt));
                if (Vm is { } fv && fv.Host.Current is { } fq)
                {
                    if (!fv.Host.Revealed) { await fv.Reveal(); await Task.Delay(3000); }
                    Services.LaunchHooks.Diag($"fixkey hook: before={string.Join("|", fv.Host.Standings.Select(j => j.Name + "=" + j.Score))}");
                    await fv.Host.ReplaceCurrent(fq with { Accepted = new[] { fixKey }, Options = fq.Options.Select((o, i) => i == fq.CorrectIndex ? fixKey : o).ToList() });
                    Services.LaunchHooks.Diag($"fixkey hook: {fv.Host.RescoreNote ?? "(no note)"} after={string.Join("|", fv.Host.Standings.Select(j => j.Name + "=" + j.Score))}");
                }
            }
            if (Services.LaunchHooks.LiveRename is { Length: > 0 } newName && Services.LaunchHooks.LiveRenameAt is { } renameAt)
            {
                await Task.Delay(TimeSpan.FromSeconds(renameAt));
                var rows = Vm?.Host.Standings ?? Array.Empty<Tidbits.Core.Networking.LiveHostNet.Joined>();
                Services.LaunchHooks.Diag($"rename hook: teams={rows.Count}");
                if (Vm is { } rv && rows.Count > 0) { var first = rows.OrderBy(j => j.Name, StringComparer.Ordinal).First(); await rv.RenameTeam(first.Id, newName); Services.LaunchHooks.Diag($"rename hook: {first.Name} -> {newName}"); }
            }
            if (Services.LaunchHooks.LiveAcceptAll is { Length: > 0 } ruling)
            {
                await Task.Delay(TimeSpan.FromSeconds(Services.LaunchHooks.LiveAcceptAt));
                if (Vm is not { } vm) return;
                if (!vm.Host.Revealed) { await vm.Reveal(); await Task.Delay(3000); }
                await vm.AcceptTextForAll(ruling);
                if (Services.LaunchHooks.LiveTieBreak) { await Task.Delay(3000); OnBreakTie(this, new RoutedEventArgs()); }
            if (Services.LaunchHooks.LiveReportAt is { } reportAt)
                {
                    await Task.Delay(TimeSpan.FromSeconds(reportAt));
                    OnNightReport(this, new RoutedEventArgs());
                }
                if (Services.LaunchHooks.LiveExportAnswers is { Length: > 0 } sheet)
                {
                    await Task.Delay(5000);
                    try { System.IO.File.WriteAllText(sheet, vm.AnswersCsv()); } catch (Exception ex) { Services.LaunchHooks.Diag($"export answers: FAILED {ex}"); }
                }
            }
        }
        catch (Exception ex) { Services.LaunchHooks.Diag($"script hooks: FAILED {ex}"); }
    }
    private bool _scriptHooksRan;

    /// TIDBITS_LIVE_PROJECTOR=1: the projector opens with the cockpit (harness).
    private void OpenProjectorFromHook()
    {
        if (!Services.LaunchHooks.LiveProjector || _projector is not null) return;
        EnsureProjector();
    }

    private void EnsureProjector()
    {
        if (_projector is not null || Vm is not { } vm) return;
        _projector = new ProjectorWindow(vm);
        _projector.Closed += (_, _) => _projector = null;
        _projector.Show();
    }

    private async void OnClose(object? sender, RoutedEventArgs e)
    {
        _projector?.Close();
        if (Vm is { } vm) await vm.Close();
        // The cockpit runs BOTH products now: Play hosts a Trivia Night, Tidbits
        // Live runs a built event. Ask the tree rather than assuming Live.
        if (this.FindAncestorOfType<PlayView>() is { } play) play.BackToPlay();
        else this.FindAncestorOfType<LiveView>()?.BackToSetup();
    }

    private void OnCyclePenalty(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => Vm?.CyclePenalty();

    private async void OnBuzzCorrect(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (Vm is { } vm) await vm.BuzzCorrect();
    }

    private void OnBuzzWrong(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => Vm?.BuzzWrong();
}
