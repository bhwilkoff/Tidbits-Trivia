using Avalonia.Controls;
using Avalonia.Interactivity;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

public partial class GameView : UserControl
{
    public GameView()
    {
        InitializeComponent();
    }

    private void OnOption(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not GameViewModel vm || vm.Engine.Current is not { } q) return;
        if (sender is Button { Content: string opt })
        {
            int idx = -1;
            for (int i = 0; i < q.Options.Count; i++)
                if (q.Options[i] == opt) { idx = i; break; }
            if (idx >= 0) vm.Submit(idx);
        }
    }

    private void OnNext(object? sender, RoutedEventArgs e) => (DataContext as GameViewModel)?.Advance();

    private void OnDone(object? sender, RoutedEventArgs e) => (DataContext as GameViewModel)?.Quit();
}
