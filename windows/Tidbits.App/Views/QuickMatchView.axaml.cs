using System;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Threading;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

/// The online Quick Match surface (2.21): a searching screen, the shared game, and
/// a win/lose/tie result. Rebuilds on the VM's Changed (marshaled — the client's
/// events fire off the SSE thread).
public partial class QuickMatchView : UserControl
{
    private QuickMatchViewModel? _vm;
    public event Action? Closed;

    // Parameterless ctor + DataContext binding (the Avalonia idiom, and it keeps the
    // XAML runtime loader / ViewLocator able to instantiate the view).
    public QuickMatchView()
    {
        InitializeComponent();
        DataContextChanged += (_, _) =>
        {
            if (_vm is not null) _vm.Changed -= OnVmChanged;
            _vm = DataContext as QuickMatchViewModel;
            if (_vm is not null) _vm.Changed += OnVmChanged;
            Render();
        };
    }

    private void OnVmChanged() => Dispatcher.UIThread.Post(Render);

    private void Render()
    {
        if (_vm is null) return;
        Root.Children.Clear();
        Root.Children.Add(_vm.Current switch
        {
            QuickMatchViewModel.Stage.Playing when _vm.Game is not null => new GameView { DataContext = _vm.Game },
            QuickMatchViewModel.Stage.Result => ResultPanel(),
            _ => SearchingPanel(),
        });
    }

    private Control SearchingPanel()
    {
        var cancel = new Button { Content = "Cancel", Classes = { "compact" }, HorizontalAlignment = HorizontalAlignment.Center };
        cancel.Click += (_, _) => { _vm.Leave(); Closed?.Invoke(); };
        return new StackPanel
        {
            Spacing = 20, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new TextBlock { Text = "Quick Match", Classes = { "view-heading" }, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock { Text = _vm.StatusLine, Classes = { "body" }, Opacity = 0.75, HorizontalAlignment = HorizontalAlignment.Center },
                new ProgressBar { IsIndeterminate = true, Width = 260 },
                new TextBlock
                {
                    Text = "Same questions for both players — best score wins.",
                    Classes = { "caption" }, HorizontalAlignment = HorizontalAlignment.Center,
                },
                cancel,
            },
        };
    }

    private Control ResultPanel()
    {
        var again = new Button { Content = "Back to Play", Classes = { "accent", "chunky" }, HorizontalAlignment = HorizontalAlignment.Center };
        again.Click += (_, _) => { _vm.Leave(); Closed?.Invoke(); };
        return new StackPanel
        {
            Spacing = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                new TextBlock { Text = _vm.StatusLine, Classes = { "view-heading" }, HorizontalAlignment = HorizontalAlignment.Center },
                new TextBlock { Text = _vm.ScoreLine, Classes = { "section-header" }, HorizontalAlignment = HorizontalAlignment.Center, Opacity = 0.85 },
                again,
            },
        };
    }
}
