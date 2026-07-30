using System;
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
            vm.PropertyChanged += (_, _) => { RefreshQr(); RefreshOptions(); };
        RefreshQr();
        RefreshOptions();
    }

    /// Build the big-screen option cards; on reveal, the correct one lights up green
    /// and the rest dim (3.38 reveal choreography).
    private void RefreshOptions()
    {
        QOptions.Children.Clear();
        var vm = DataContext as LiveHostViewModel;
        var options = vm?.Host.Current?.Options;
        if (options is null) return;
        int? correct = vm!.RevealCorrectIndex;
        for (int i = 0; i < options.Count; i++)
        {
            bool isCorrect = correct == i;
            bool revealed = correct is not null;
            QOptions.Children.Add(new Border
            {
                Padding = new Avalonia.Thickness(24, 18),
                Margin = new Avalonia.Thickness(0, 6),
                CornerRadius = new Avalonia.CornerRadius(12),
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(isCorrect ? "#3FCF8E" : "#1C1C28")),
                Opacity = revealed && !isCorrect ? 0.4 : 1.0,
                Child = new TextBlock
                {
                    Text = options[i],
                    Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(isCorrect ? "#0A0A12" : "#FFFFFF")),
                    FontSize = 40,
                    FontWeight = isCorrect ? Avalonia.Media.FontWeight.Black : Avalonia.Media.FontWeight.Normal,
                },
            });
        }
    }

    private string _leadUrl = "";

    private void RefreshQr()
    {
        var vm = DataContext as LiveHostViewModel;
        var code = vm?.Host.Code ?? "";
        if (code.Length > 0 && code != _qrCode)
        {
            _qrCode = code;
            try { LobbyQr.Source = QrHelper.Generate(QrHelper.JoinUrl(code), 10); } catch { }
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
