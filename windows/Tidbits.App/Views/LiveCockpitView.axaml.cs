using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.VisualTree;
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
    }

    private void RefreshCountdown()
    {
        var s = Vm?.SecondsRemaining;
        CountdownText.Text = s is { } n ? $"{n}s" : "";
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (Vm is { } vm) vm.PropertyChanged += (_, _) => { RefreshQr(); RefreshTally(); };
        RefreshQr();
        RefreshTally();
    }

    /// Rebuild the options with a live per-option answer-distribution bar. The
    /// correct option is tinted green on reveal.
    private void RefreshTally()
    {
        OptionsTally.Children.Clear();
        var host = Vm?.Host;
        if (host?.Current is not { } q || q.Options.Count == 0) return;

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
    private async void OnBack(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Back(); }

    private async void OnTimer30(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.StartTimer(30); RefreshCountdown(); }
    private async void OnTimer60(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.StartTimer(60); RefreshCountdown(); }
    private async void OnAdd15(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.AddTime(15); RefreshCountdown(); }
    private async void OnAdd30(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.AddTime(30); RefreshCountdown(); }
    private async void OnClearTimer(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.ClearTimer(); RefreshCountdown(); }

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
        this.FindAncestorOfType<LiveView>()?.BackToSetup();
    }
}
