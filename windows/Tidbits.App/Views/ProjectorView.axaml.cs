using System;
using Avalonia.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class ProjectorView : UserControl
{
    private string _qrCode = "";
    private readonly Avalonia.Threading.DispatcherTimer _tick;

    public ProjectorView()
    {
        InitializeComponent();
        _tick = new Avalonia.Threading.DispatcherTimer(
            TimeSpan.FromSeconds(1), Avalonia.Threading.DispatcherPriority.Normal, (_, _) => RefreshCountdown());
        _tick.Start();
        DetachedFromVisualTree += (_, _) => _tick.Stop();
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
