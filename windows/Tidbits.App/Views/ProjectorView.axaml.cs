using System;
using Avalonia.Controls;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class ProjectorView : UserControl
{
    private string _qrCode = "";

    public ProjectorView()
    {
        InitializeComponent();
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
