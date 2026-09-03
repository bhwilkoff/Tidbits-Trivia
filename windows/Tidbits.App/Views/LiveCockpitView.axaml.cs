using System;
using System.Linq;
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
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto"), Margin = new Avalonia.Thickness(0, 2, 0, 0) };
            grid.Children.Add(new TextBlock
            {
                Text = $"{row.Name}: “{row.Text}”", TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                Opacity = row.AutoCorrect ? 1 : 0.75,
            });
            var verdict = new TextBlock
            {
                Text = row.AutoCorrect ? "✓" : "✗", FontWeight = FontWeight.Black,
                Foreground = new SolidColorBrush(Color.Parse(row.AutoCorrect ? "#1E9E6A" : "#D64545")),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Margin = new Avalonia.Thickness(8, 0),
            };
            Grid.SetColumn(verdict, 1);
            grid.Children.Add(verdict);
            if (!row.AutoCorrect)
            {
                var accept = new Button { Content = "Accept", Padding = new Avalonia.Thickness(10, 3), FontSize = 12, Tag = row.Uid };
                accept.Click += OnAcceptText;
                Grid.SetColumn(accept, 2);
                grid.Children.Add(accept);
            }
            ReviewPanel.Children.Add(grid);
        }
    }

    private async void OnAcceptText(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            await vm.AcceptText(uid);
    }

    /// Rebuild the options with a live per-option answer-distribution bar. The
    /// correct option is tinted green on reveal.
    private void RefreshTally()
    {
        OptionsTally.Children.Clear();
        var host = Vm?.Host;
        if (host?.Current is not { } q || q.Options.Count == 0) return;
        // G5: while the pick-a-category grid is up the room has not chosen a cell,
        // so there is no live question — and these bars were still listing the
        // OPTIONS of the one the host happens to be sitting on. A host reading
        // four answers to a question nobody asked is the same confusion the
        // hidden Reveal button caused.
        if (Vm is { ShowBoardScreen: true }) return;

        var dist = host.AnswerDistribution;
        int max = dist.Count > 0 ? Math.Max(1, dist.Max()) : 1;
        bool reveal = host.Revealed;

        for (int i = 0; i < q.Options.Count; i++)
        {
            int count = i < dist.Count ? dist[i] : 0;
            bool correct = reveal && i == q.CorrectIndex;

            var bar = new Border
            {
                Height = 34, CornerRadius = new Avalonia.CornerRadius(8),
                Background = new Avalonia.Media.SolidColorBrush(
                    Avalonia.Media.Color.Parse(correct ? "#3320A060" : "#14808080")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                Width = 60 + (500.0 * count / max),
                MinWidth = 60,
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
            var stack = new Panel();          // the bar sits behind the label + count
            stack.Children.Add(bar);
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

    private async void OnReveal(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Reveal(); }
    private async void OnNext(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Next(); }
    private async void OnLock(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Lock(); }
    private async void OnSkip(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Skip(); }
    private void OnToggleHold(object? sender, RoutedEventArgs e) => Vm?.ToggleHold();

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
        var panel = new StackPanel { Spacing = 8, MinWidth = 300 };
        panel.Children.Add(new TextBlock { Text = "Brains-only tie-break — pick the winner. They get +1 to take the lead.", TextWrapping = TextWrapping.Wrap, Opacity = 0.75 });
        panel.Children.Add(pick);
        var dlg = new FAContentDialog { Title = "Break the tie", Content = panel, PrimaryButtonText = "Award +1", CloseButtonText = "Cancel" };
        if (await dlg.ShowAsync() == FAContentDialogResult.Primary
            && pick.SelectedItem is Tidbits.Core.Networking.LiveHostNet.Joined w)
            await vm.BreakTie(w.Id);
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
        var html = Tidbits.Core.Networking.LiveExport.StandingsHtml(vm.Host.Standings, $"{vm.Host.Title} — Standings");
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
    private void OnPlayQuestionClip(object? sender, RoutedEventArgs e)
    {
        if (Vm?.CurrentClipPath is not { } path) return;
        Services.GameData.Shared.Value.Av.PlayClip(path);
    }

    private void OnStopQuestionClip(object? sender, RoutedEventArgs e) =>
        Services.GameData.Shared.Value.Av.StopClip();

    private ProjectorWindow? _projector;

    private void OnProjector(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        if (_projector is not null) { _projector.Activate(); return; }
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
