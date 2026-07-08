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
        if (DataContext is LiveHostViewModel vm) vm.PropertyChanged += (_, _) => RefreshQr();
        RefreshQr();
    }

    private void RefreshQr()
    {
        var code = (DataContext as LiveHostViewModel)?.Host.Code ?? "";
        if (code.Length == 0 || code == _qrCode) return;
        _qrCode = code;
        try { LobbyQr.Source = QrHelper.Generate(QrHelper.JoinUrl(code), 10); } catch { }
    }
}
