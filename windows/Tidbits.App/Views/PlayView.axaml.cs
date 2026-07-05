using Avalonia.Controls;
using Avalonia.Interactivity;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;

namespace Tidbits.App.Views;

public partial class PlayView : UserControl
{
    public PlayView()
    {
        InitializeComponent();
    }

    private async void OnQuickPlay(object? sender, RoutedEventArgs e)
    {
        var engine = GameData.Shared.Value.NewEngine();
        var vm = new GameViewModel(engine);
        vm.Closed += () =>
        {
            GameHost.Content = null;
            Landing.IsVisible = true;
        };
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        await engine.Start(GameMode.Classic, TriviaCategory.Named("mixed"));
    }
}
