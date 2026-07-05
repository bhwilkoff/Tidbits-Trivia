using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class LiveCockpitView : UserControl
{
    public LiveCockpitView()
    {
        InitializeComponent();
    }

    private LiveHostViewModel? Vm => DataContext as LiveHostViewModel;

    private async void OnReveal(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Reveal(); }
    private async void OnNext(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Next(); }
    private async void OnLock(object? sender, RoutedEventArgs e) { if (Vm is { } vm) await vm.Lock(); }

    private async void OnClose(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm) await vm.Close();
        this.FindAncestorOfType<LiveView>()?.BackToSetup();
    }
}
