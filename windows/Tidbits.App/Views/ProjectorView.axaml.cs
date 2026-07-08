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
