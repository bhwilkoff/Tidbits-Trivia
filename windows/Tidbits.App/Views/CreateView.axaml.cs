using Avalonia.Controls;
using Avalonia.Interactivity;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;

namespace Tidbits.App.Views;

public partial class CreateView : UserControl
{
    public CreateView()
    {
        InitializeComponent();
    }

    private async void OnGenerate(object? sender, RoutedEventArgs e)
    {
        var topic = TopicBox.Text?.Trim() ?? "";
        if (topic.Length < 2) { Status("Type a topic to generate a quiz."); return; }

        GenBtn.IsEnabled = false;
        Status("Building your quiz…");
        var questions = await GameData.Shared.Value.Provider.CreateQuestions(topic, 10);
        GenBtn.IsEnabled = true;

        if (questions.Count == 0)
        {
            Status($"No questions found for “{topic}” — try a broader topic.");
            return;
        }

        var engine = GameData.Shared.Value.NewEngine();
        var vm = new GameViewModel(engine, GameData.Shared.Value.Records);
        vm.Closed += () =>
        {
            GameHost.Content = null;
            Landing.IsVisible = true;
        };
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), questions);
    }

    private void Status(string text)
    {
        StatusText.Text = text;
        StatusText.IsVisible = true;
    }
}
