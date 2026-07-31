using System.Collections.Generic;
using System.Linq;
using Avalonia.Automation;
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
        // Migrate off the pre-contract saved-sets format (QUIZ-CONTRACT §7) before
        // listing, so a returning player's sets appear in the new shelf rather than
        // silently vanishing. Safe here: the sources are already loaded by the time
        // any view is constructed, which is the ordering the web version got wrong.
        var data = GameData.Shared.Value;
        if (QuizMigration.Run(data.SavedSets, data.Quizzes, data.Sources) > 0)
            data.SavedSets.Clear();
        BuildSaved();
    }

    private async void OnGenerate(object? sender, RoutedEventArgs e)
    {
        var topic = TopicBox.Text?.Trim() ?? "";
        if (topic.Length < 2) { Status("Type a topic to generate a quiz."); return; }

        GenBtn.IsEnabled = false;
        GenProgress.IsVisible = true;              // loading state
        Status("Building your quiz…");
        var questions = await GameData.Shared.Value.Provider.CreateQuestions(topic, 10);
        GenBtn.IsEnabled = true;
        GenProgress.IsVisible = false;

        if (questions.Count == 0)
        {
            Status($"No questions found for “{topic}” — try a broader topic.");
            return;
        }

        // Every created quiz is saved automatically — the player never has to notice
        // a Save button to keep what they made.
        var gd = GameData.Shared.Value;
        gd.Quizzes.SaveCreated(questions, topic, gd.Rtdb.Uid ?? "local", gd.PlayerName);
        BuildSaved();
        Play(questions);
    }

    /// Import hand-authored questions from a CSV → save as a replayable set.
    private async void OnImportCsv(object? sender, RoutedEventArgs e)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top is null) return;
        var files = await top.StorageProvider.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = "Import questions (CSV)", AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new Avalonia.Platform.Storage.FilePickerFileType("CSV") { Patterns = new[] { "*.csv" } },
            },
        });
        var file = files.FirstOrDefault();
        if (file is null) return;

        string text;
        using (var stream = await file.OpenReadAsync())
        using (var reader = new System.IO.StreamReader(stream))
            text = await reader.ReadToEndAsync();

        var questions = Tidbits.Core.Data.CsvQuestions.Parse(text);
        if (questions.Count == 0) { Status("No valid questions found in that CSV."); return; }

        var label = System.IO.Path.GetFileNameWithoutExtension(file.Name);
        var gdi = GameData.Shared.Value;
        gdi.Quizzes.SaveCreated(questions, string.IsNullOrWhiteSpace(label) ? "Imported" : label,
                                gdi.Rtdb.Uid ?? "local", gdi.PlayerName);
        Status($"Imported {questions.Count} questions — saved below.");
        BuildSaved();
    }

    /// Retained only for the CSV-import path; Create itself auto-saves. It writes to
    /// the CONTRACT store, never the legacy one the migration just cleared -- a
    /// writer left behind would resurrect the old format on the next launch.
    private void OnSaveSet(object? sender, RoutedEventArgs e)
    {
        if (_lastQuestions is not { Count: > 0 }) return;
        var gd = GameData.Shared.Value;
        gd.Quizzes.SaveCreated(_lastQuestions, _lastLabel, gd.Rtdb.Uid ?? "local", gd.PlayerName);
        SaveBtn.IsVisible = false;
        BuildSaved();
    }

    /// The persisted Create sets — each replayable, each removable.
    private void BuildSaved()
    {
        SavedPanel.Children.Clear();
        var data = GameData.Shared.Value;
        var quizzes = data.Quizzes.All();
        SavedHeader.IsVisible = true;
        SavedHeader.Text = "Your quizzes";
        if (quizzes.Count == 0)
        {
            // The empty line teaches the mechanic on first run rather than leaving a
            // blank wall (universal-feature-states).
            SavedPanel.Children.Add(new TextBlock
            {
                Text = "Quizzes you make are saved here automatically, ready to replay.",
                Opacity = 0.72, TextWrapping = Avalonia.Media.TextWrapping.Wrap, FontSize = 14,
            });
            return;
        }
        foreach (var q in quizzes)
        {
            var set = q;
            var row = new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
            grid.Children.Add(new TextBlock
            {
                Text = $"{set.Title} · {set.QuestionCount} Qs", FontWeight = Avalonia.Media.FontWeight.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
            });
            var play = new Button { Content = "Play", Padding = new Avalonia.Thickness(14, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            play.Classes.Add("accent");
            play.Click += (_, _) =>
            {
                // A quiz can legitimately come up short (an older corpus, a set this
                // build lacks), so say so rather than padding it with other questions.
                var r = QuizStore.ResolveForPlay(set, data.Sources.Corpus, data.Sources);
                if (!r.IsPlayable)
                {
                    Status($"This quiz needs questions your version doesn't have yet. Try creating it again from “{set.Topic}”.");
                    return;
                }
                if (!r.IsComplete)
                    Status($"{r.Missing} of this quiz's {set.QuestionCount} questions aren't in your version yet.");
                Play(r.Questions);
            };
            Grid.SetColumn(play, 1);
            grid.Children.Add(play);
            var del = new Button { Content = "✕", Padding = new Avalonia.Thickness(10, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            AutomationProperties.SetName(del, $"Delete quiz {set.Title}");
            del.Click += (_, _) => { data.Quizzes.Delete(set.Id); BuildSaved(); };
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
