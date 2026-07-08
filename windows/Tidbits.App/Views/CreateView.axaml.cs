using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class CreateView : UserControl
{
    private List<Question>? _lastQuestions;
    private string _lastLabel = "";

    public CreateView()
    {
        InitializeComponent();
        BuildSaved();
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

        _lastQuestions = questions;
        _lastLabel = topic;
        SaveBtn.Content = $"Save “{topic}” ({questions.Count})";
        SaveBtn.IsVisible = true;
        Play(questions);
    }

    private void OnSaveSet(object? sender, RoutedEventArgs e)
    {
        if (_lastQuestions is not { Count: > 0 }) return;
        GameData.Shared.Value.SavedSets.Add(_lastLabel, _lastQuestions);
        SaveBtn.IsVisible = false;
        BuildSaved();
    }

    /// The persisted Create sets — each replayable, each removable.
    private void BuildSaved()
    {
        SavedPanel.Children.Clear();
        var sets = GameData.Shared.Value.SavedSets.All;
        SavedHeader.IsVisible = sets.Count > 0;
        foreach (var s in sets)
        {
            var set = s;
            var row = new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
            grid.Children.Add(new TextBlock
            {
                Text = $"{set.Label} · {set.Count} Qs", FontWeight = Avalonia.Media.FontWeight.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
            });
            var play = new Button { Content = "Play", Padding = new Avalonia.Thickness(14, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            play.Classes.Add("accent");
            play.Click += (_, _) => Play(new List<Question>(set.Questions));
            Grid.SetColumn(play, 1);
            grid.Children.Add(play);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(10, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            del.Click += (_, _) => { GameData.Shared.Value.SavedSets.Remove(set.Id); BuildSaved(); };
            Grid.SetColumn(del, 2);
            grid.Children.Add(del);
            row.Child = grid;
            SavedPanel.Children.Add(row);
        }
    }

    private void Play(IReadOnlyList<Question> questions)
    {
        var engine = GameData.Shared.Value.NewEngine();
        var vm = new GameViewModel(engine, GameData.Shared.Value.Records);
        vm.Closed += () => { GameHost.Content = null; Landing.IsVisible = true; };
        vm.PlayAgainRequested += () => Play(questions);
        Landing.IsVisible = false;
        GameHost.Content = new GameView { DataContext = vm };
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), new List<Question>(questions));
    }

    private void Status(string text)
    {
        StatusText.Text = text;
        StatusText.IsVisible = true;
    }
}
