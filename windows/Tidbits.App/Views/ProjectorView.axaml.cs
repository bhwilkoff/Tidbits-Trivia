using System;
using System.Linq;
using Avalonia.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class ProjectorView : UserControl
{
    private string _qrCode = "";
    private readonly Avalonia.Threading.DispatcherTimer _tick;
    private VideoFrameSink? _sink;

    public ProjectorView()
    {
        InitializeComponent();
        _tick = new Avalonia.Threading.DispatcherTimer(
            TimeSpan.FromSeconds(1), Avalonia.Threading.DispatcherPriority.Normal, (_, _) => RefreshCountdown());
        _tick.Start();
        AttachedToVisualTree += (_, _) => AttachVideo();
        DetachedFromVisualTree += (_, _) =>
        {
            _tick.Stop();
            // Detach before disposing: LibVLC writes frames from its own thread, and a sink
            // freed while the player still holds it is a use-after-free on the big screen.
            GameData.Shared.Value.Av.SetVideoSink(null);
            Video.Sink = null;
            _sink?.Dispose();
            _sink = null;
        };
    }

    /// Route the question clip's picture into this window. The projector is the ONLY
    /// surface that should show video — the cockpit is the host's private view, and a clip
    /// mirrored there would just be a second thing to look away from.
    private void AttachVideo()
    {
        if (_sink is not null) return;
        var av = GameData.Shared.Value.Av;
        if (!av.Available) return;                 // no LibVLC natives (e.g. headless CI)
        _sink = new VideoFrameSink();
        _sink.FrameArrived += () => Video.IsVisible = true;
        Video.Sink = _sink;
        av.SetVideoSink(_sink);

        // Hide again when the clip ends or is stopped, or the last frame stays frozen on
        // the big screen over the next question. These fire on a LibVLC thread.
        if (av.ClipPlayer is { } clip)
        {
            void Hide(object? _, EventArgs __) =>
                Avalonia.Threading.Dispatcher.UIThread.Post(() => Video.IsVisible = false);
            clip.EndReached += Hide;
            clip.Stopped += Hide;
        }
    }

    private void RefreshCountdown()
    {
        var s = (DataContext as LiveHostViewModel)?.SecondsRemaining;
        CountdownBig.Text = s is { } n ? $"{n}s" : "";
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (DataContext is LiveHostViewModel vm)
            vm.PropertyChanged += (_, _) => { RefreshQr(); RefreshOptions(); RefreshChips(); RefreshPicture(); };
        RefreshQr();
        RefreshOptions();
        RefreshChips();
        RefreshPicture();
    }

    /// Build the big-screen option rows; with the tally on, each carries a vote bar
    /// and its count. On reveal the correct one lights up green and the rest dim
    /// (3.38 reveal choreography).
    private void RefreshOptions()
    {
        QOptions.Children.Clear();
        var vm = DataContext as LiveHostViewModel;
        var options = vm?.Host.Current?.Options;
        if (options is null) return;
        int? correct = vm!.RevealCorrectIndex;
        bool revealed = correct is not null;
        bool tally = vm.ShowTally;
        var counts = tally ? vm.OptionTallies : System.Array.Empty<int>();
        int total = System.Math.Max(counts.Sum(), 1);
        for (int i = 0; i < options.Count; i++)
        {
            bool isCorrect = correct == i;
            var label = new TextBlock
            {
                Text = options[i],
                Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(isCorrect ? "#0A0A12" : "#FFFFFF")),
                FontSize = tally ? 24 : 32,
                FontWeight = isCorrect ? Avalonia.Media.FontWeight.Black : Avalonia.Media.FontWeight.SemiBold,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
            };
            Control content = label;
            if (tally)
            {
                var n = i < counts.Count ? counts[i] : 0;
                var bar = new Border
                {
                    Height = 18, CornerRadius = new Avalonia.CornerRadius(9),
                    Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#33FFFFFF")),
                    VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                    Child = new Border
                    {
                        CornerRadius = new Avalonia.CornerRadius(9), HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                        Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(isCorrect ? "#0A0A12" : "#FF5C35")),
                        Width = System.Math.Max(12, 520.0 * n / total),
                    },
                };
                var count = new TextBlock
                {
                    Text = n.ToString(), FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Black, Width = 48,
                    TextAlignment = Avalonia.Media.TextAlignment.Right,
                    Foreground = label.Foreground, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                };
                var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,540,Auto") };
                Grid.SetColumn(bar, 1); Grid.SetColumn(count, 2);
                bar.Margin = new Avalonia.Thickness(16, 0);
                row.Children.Add(label); row.Children.Add(bar); row.Children.Add(count);
                content = row;
            }
            QOptions.Children.Add(new Border
            {
                Padding = new Avalonia.Thickness(20, tally ? 8 : 12),
                Margin = new Avalonia.Thickness(0, 3),
                CornerRadius = new Avalonia.CornerRadius(12),
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(isCorrect ? "#3FCF8E" : "#1C1C28")),
                Opacity = revealed && !isCorrect ? 0.4 : 1.0,
                Child = content,
            });
        }
    }

    /// The team STRIP: the top five as chips that wrap — a strip, not a column.
    private void RefreshChips()
    {
        TeamChips.Children.Clear();
        var vm = DataContext as LiveHostViewModel;
        if (vm is null || !vm.ShowTeams) return;
        var chips = vm.TeamChips;
        if (chips.Count == 0)
        {
            TeamChips.Children.Add(new TextBlock
            {
                Text = "Teams appear here as they join.", FontSize = 18, Opacity = 0.6,
                Foreground = Avalonia.Media.Brushes.White, Margin = new Avalonia.Thickness(0, 6),
            });
            return;
        }
        foreach (var t in chips)
        {
            bool lead = t.Rank == 1;
            var row = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
            row.Children.Add(new TextBlock
            {
                Text = lead ? "♛" : t.Rank.ToString(), FontSize = 16, FontWeight = Avalonia.Media.FontWeight.Black,
                Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(lead ? "#0A0A12" : "#99FFFFFF")),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            row.Children.Add(new TextBlock
            {
                Text = t.Name, FontSize = 18, FontWeight = Avalonia.Media.FontWeight.Bold, MaxWidth = 260,
                TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
                Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(lead ? "#0A0A12" : "#FFFFFF")),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            row.Children.Add(new TextBlock
            {
                Text = t.Score.ToString(), FontSize = 20, FontWeight = Avalonia.Media.FontWeight.Black,
                Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(lead ? "#0A0A12" : "#FFFFFF")),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            TeamChips.Children.Add(new Border
            {
                Padding = new Avalonia.Thickness(14, 8), Margin = new Avalonia.Thickness(0, 0, 8, 8),
                CornerRadius = new Avalonia.CornerRadius(12),
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(lead ? "#FFC93C" : "#1C1C28")),
                BorderBrush = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#47FFFFFF")), BorderThickness = new Avalonia.Thickness(2),
                Child = row,
            });
        }
    }

    /// 3.36: the question's picture through the shared ImageCache (store refs resolve there).
    private string _pictureUrl = "";
    private void RefreshPicture()
    {
        var vm = DataContext as LiveHostViewModel;
        var url = vm?.PictureUrl ?? "";
        if (url == _pictureUrl) return;
        _pictureUrl = url;
        Picture.Source = null; PictureHint.IsVisible = true; PictureHint.Text = "Loading picture…";
        if (url.Length == 0) return;
        if (Services.ImageCache.Shared.Cached(url) is { } cached) { Picture.Source = cached; PictureHint.IsVisible = false; return; }
        Services.ImageCache.Shared.LoadAsync(url).ContinueWith(t =>
            Avalonia.Threading.Dispatcher.UIThread.Post(() =>
            {
                if (_pictureUrl != url) return;   // the question moved on
                if (t.Status == System.Threading.Tasks.TaskStatus.RanToCompletion && t.Result is { } bmp) { Picture.Source = bmp; PictureHint.IsVisible = false; }
                else PictureHint.Text = "Picture unavailable";
            }));
    }

    private string _leadUrl = "";

    private void RefreshQr()
    {
        var vm = DataContext as LiveHostViewModel;
        var code = vm?.Host.Code ?? "";
        if (code.Length > 0 && code != _qrCode)
        {
            _qrCode = code;
            try
            {
                LobbyQr.Source = QrHelper.Generate(QrHelper.JoinUrl(code), 10);
                JoinQr.Source = QrHelper.Generate(QrHelper.JoinUrl(code), 4);
            }
            catch { }
        }
        // Lead-capture QR (Wave D) — points at the venue's mailing-list URL.
        var lead = vm?.LeadCaptureUrl ?? "";
        if (lead.Length > 0 && lead != _leadUrl)
        {
            _leadUrl = lead;
            try { LeadQr.Source = QrHelper.Generate(lead, 8); } catch { }
        }
    }
}
