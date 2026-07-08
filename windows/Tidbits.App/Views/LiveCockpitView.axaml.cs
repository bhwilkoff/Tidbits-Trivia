using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.VisualTree;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class LiveCockpitView : UserControl
{
    private string _qrCode = "";

    public LiveCockpitView()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (Vm is { } vm) vm.PropertyChanged += (_, _) => RefreshQr();
        RefreshQr();
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

    // Manual score override — the team uid rides the button's Tag.
    private async void OnScoreUp(object? sender, RoutedEventArgs e) => await Adjust(sender, +1);
    private async void OnScoreDown(object? sender, RoutedEventArgs e) => await Adjust(sender, -1);

    private async System.Threading.Tasks.Task Adjust(object? sender, int delta)
    {
        if (Vm is { } vm && (sender as Control)?.Tag is string uid && uid.Length > 0)
            await vm.Adjust(uid, delta);
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
