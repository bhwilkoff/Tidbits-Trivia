using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;

namespace Tidbits.App.Views;

/// The per-question editor — WINDOWS-DESIGN §6.6, the mirror of macOS §A2.4.
///
/// Before this, a Windows round was `{kind, count}` and the questions were pulled
/// from the corpus at host time, so there was literally nothing for a host to open
/// and fix. Every format the builder offers gets its own answer payload here; the
/// host never sees fields that cannot apply to the round they are editing.
public static class LiveQuestionEditorDialog
{
    /// Returns the edited question, or null if the host cancelled.
    public static async Task<Question?> ShowAsync(Question question, GameMode format, string title)
    {
        var promptBox = new TextBox
        {
            Text = question.Prompt, AcceptsReturn = true, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            MinHeight = 62, PlaceholderText = "What is the question?",
        };
        AutomationProperties.SetName(promptBox, "Question prompt");

        var categoryBox = new ComboBox { MinWidth = 160, ItemsSource = TriviaCategory.All.ToList() };
        categoryBox.SelectedItem = TriviaCategory.All.FirstOrDefault(c => c.Id == question.CategoryId)
                                   ?? TriviaCategory.Named("mixed");
        AutomationProperties.SetName(categoryBox, "Category");

        var difficultyBox = new ComboBox
        {
            MinWidth = 120,
            ItemsSource = new[] { "1 · Easy", "2", "3 · Medium", "4", "5 · Hard" },
            SelectedIndex = Math.Clamp(question.Difficulty, 1, 5) - 1,
        };
        AutomationProperties.SetName(difficultyBox, "Difficulty");

        var explanationBox = new TextBox
        {
            Text = question.Explanation, AcceptsReturn = true, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            MinHeight = 54, PlaceholderText = "Read out after the answer (optional)",
        };
        AutomationProperties.SetName(explanationBox, "Explanation");

        var payload = BuildPayload(question, format, out var readBack);

        var problem = new FAInfoBar
        {
            Severity = FAInfoBarSeverity.Warning, IsClosable = false, IsOpen = false,
            Title = "Not ready", Margin = new Avalonia.Thickness(0, 6, 0, 0),
        };

        var body = new StackPanel { Spacing = 10, MinWidth = 520 };
        body.Children.Add(Labelled("Question", promptBox));
        var meta = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        meta.Children.Add(Labelled("Category", categoryBox));
        meta.Children.Add(Labelled("Difficulty", difficultyBox));
        body.Children.Add(meta);
        body.Children.Add(payload);
        body.Children.Add(Labelled("Reveal", explanationBox));
        body.Children.Add(problem);

        var dialog = new FAContentDialog
        {
            Title = title,
            PrimaryButtonText = "Save",
            CloseButtonText = "Cancel",
            DefaultButton = FAContentDialogButton.Primary,
            Content = new ScrollViewer { Content = body, MaxHeight = 520 },
        };

        Question? result = null;
        dialog.PrimaryButtonClick += (_, args) =>
        {
            var draft = question with
            {
                Prompt = promptBox.Text?.Trim() ?? "",
                CategoryId = (categoryBox.SelectedItem as TriviaCategory)?.Id ?? "mixed",
                Difficulty = difficultyBox.SelectedIndex + 1,
                Explanation = explanationBox.Text?.Trim() ?? "",
            };
            draft = readBack(draft);
            var issues = Problems(draft, format);
            if (issues.Count > 0)
            {
                // Keep the dialog open and say what is wrong, rather than saving a
                // question that cannot be played and surfacing it mid-night.
                args.Cancel = true;
                problem.Message = issues[0];
                problem.IsOpen = true;
                return;
            }
            result = draft;
        };

        await dialog.ShowAsync();
        return result;
    }

    private static Control Labelled(string label, Control control)
    {
        var stack = new StackPanel { Spacing = 3 };
        stack.Children.Add(new TextBlock { Text = label, Classes = { "caption" }, Opacity = 0.72 });
        stack.Children.Add(control);
        return stack;
    }

    private static TextBox Lines(string? label, IEnumerable<string>? values, string placeholder, double minHeight = 92)
    {
        var box = new TextBox
        {
            Text = values is null ? "" : string.Join(Environment.NewLine, values),
            AcceptsReturn = true, MinHeight = minHeight, PlaceholderText = placeholder,
        };
        if (label is not null) AutomationProperties.SetName(box, label);
        return box;
    }

    private static List<string> Split(string? text) =>
        (text ?? "").Split('\n').Select(s => s.Trim('\r', ' ', '\t')).Where(s => s.Length > 0).ToList();

    /// The format-specific answer payload, plus the closure that reads it back onto
    /// a draft. One question shape per format.
    private static Control BuildPayload(Question q, GameMode format, out Func<Question, Question> readBack)
    {
        switch (format)
        {
            case GameMode.ClosestCall:
            {
                var answer = new TextBox { Text = (q.Closest?.Answer ?? 0).ToString(), MinWidth = 110 };
                var unit = new TextBox { Text = q.Closest?.Unit ?? "", PlaceholderText = "unit (optional)", MinWidth = 110 };
                var lo = new TextBox { Text = (q.Closest?.Min ?? 0).ToString(), MinWidth = 90 };
                var hi = new TextBox { Text = (q.Closest?.Max ?? 100).ToString(), MinWidth = 90 };
                var step = new TextBox { Text = (q.Closest?.Step ?? 1).ToString(), MinWidth = 90 };
                var tol = new TextBox { Text = (q.Closest?.Tolerance ?? 10).ToString(), MinWidth = 90 };
                AutomationProperties.SetName(answer, "Numeric answer");
                var grid = new StackPanel { Spacing = 8 };
                grid.Children.Add(Row(Labelled("Answer", answer), Labelled("Unit", unit)));
                grid.Children.Add(Row(Labelled("Range low", lo), Labelled("Range high", hi),
                                      Labelled("Step", step), Labelled("Tolerance", tol)));
                readBack = draft => draft with
                {
                    Closest = new ClosestSpec
                    {
                        Answer = Num(answer.Text), Min = Num(lo.Text), Max = Num(hi.Text, 100),
                        Step = Num(step.Text, 1), Tolerance = Num(tol.Text, 10), Unit = unit.Text?.Trim() ?? "",
                    },
                };
                return Labelled("Closest Call", grid);
            }
            case GameMode.Ordering:
            {
                var box = Lines("Items in correct order", q.Ordering, "One item per line, in the CORRECT order. The room sees them shuffled.", 120);
                readBack = draft => draft with { Ordering = Split(box.Text) };
                return Labelled("Items, in the CORRECT order", box);
            }
            case GameMode.Matching:
            {
                var keys = Lines("Keys", q.Matching?.Keys, "One key per line");
                var values = Lines("Matches", q.Matching?.Values, "Line 1 pairs with line 1");
                readBack = draft =>
                {
                    var k = Split(keys.Text); var v = Split(values.Text);
                    return draft with { Matching = new MatchSpec { Keys = k, Values = v } };
                };
                return Labelled("Pairs (line 1 pairs with line 1)", Row(Labelled("Keys", keys), Labelled("Matches", values)));
            }
            case GameMode.Enumerate:
            {
                var box = Lines("Accepted answers",
                                q.Enumerate?.Groups.Select(g => string.Join(", ", g)),
                                "One answer per line. Aliases on the same line, comma-separated.", 120);
                readBack = draft => draft with
                {
                    Enumerate = new EnumSpec
                    {
                        Groups = Split(box.Text)
                            .Select(l => l.Split(',').Select(x => x.Trim()).Where(x => x.Length > 0).ToList())
                            .Where(g => g.Count > 0).Cast<IReadOnlyList<string>>().ToList(),
                    },
                };
                return Labelled("Accepted answers", box);
            }
            case GameMode.TypeAnswer:
            {
                var box = Lines("Accepted answers", q.Accepted ?? [q.CorrectAnswer],
                                "One per line. Spelling leniency applies on top; the host can still mark any answer correct live.");
                readBack = draft => draft with { Accepted = Split(box.Text) };
                return Labelled("Accepted answers", box);
            }
            default:
            {
                var boxes = new List<TextBox>();
                var radios = new List<RadioButton>();
                var stack = new StackPanel { Spacing = 6 };
                for (int i = 0; i < 4; i++)
                {
                    var text = i < q.Options.Count ? q.Options[i] : "";
                    var tb = new TextBox { Text = text, PlaceholderText = $"Choice {i + 1}", MinWidth = 360 };
                    AutomationProperties.SetName(tb, $"Choice {i + 1}");
                    var radio = new RadioButton { GroupName = "correct", IsChecked = q.CorrectIndex == i, Content = "Correct" };
                    AutomationProperties.SetName(radio, $"Choice {i + 1} is correct");
                    boxes.Add(tb); radios.Add(radio);
                    stack.Children.Add(Row(radio, tb));
                }
                readBack = draft =>
                {
                    var texts = boxes.Select(b => b.Text?.Trim() ?? "").ToList();
                    int chosen = radios.FindIndex(r => r.IsChecked == true);
                    if (chosen < 0) chosen = 0;
                    var correct = chosen < texts.Count ? texts[chosen] : "";
                    // Drop blank slots but keep the correct answer's index pointing at
                    // the same STRING — a blank slot renders as an empty tappable choice.
                    var kept = texts.Where(t => t.Length > 0).ToList();
                    if (kept.Count == 0) kept.Add(correct.Length > 0 ? correct : "—");
                    int ci = Math.Max(0, kept.IndexOf(correct));
                    return draft with { Options = kept, CorrectIndex = ci };
                };
                return Labelled("Choices", stack);
            }
        }
    }

    private static Control Row(params Control[] children)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        foreach (var c in children) row.Children.Add(c);
        return row;
    }

    private static double Num(string? s, double fallback = 0) =>
        double.TryParse(s, System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : fallback;

    /// The problems that would make this question unplayable, in the host's words.
    public static List<string> Problems(Question q, GameMode format)
    {
        var problems = new List<string>();
        if (string.IsNullOrWhiteSpace(q.Prompt)) problems.Add("The question needs a prompt.");
        switch (format)
        {
            case GameMode.TypeAnswer:
                if ((q.Accepted?.Count ?? 0) == 0)
                    problems.Add("A type-the-answer question needs at least one accepted answer.");
                break;
            case GameMode.ClosestCall:
                if (q.Closest is null) problems.Add("A Closest Call question needs a numeric answer.");
                else if (q.Closest.Min >= q.Closest.Max) problems.Add("The range low must be below the range high.");
                else if (q.Closest.Answer < q.Closest.Min || q.Closest.Answer > q.Closest.Max)
                    problems.Add("The answer sits outside the range.");
                else if (q.Closest.Tolerance <= 0) problems.Add("Tolerance must be above zero.");
                break;
            case GameMode.Ordering:
                if ((q.Ordering?.Count ?? 0) < 3) problems.Add("An ordering question needs at least 3 items.");
                break;
            case GameMode.Matching:
                var k = q.Matching?.Keys.Count ?? 0;
                var v = q.Matching?.Values.Count ?? 0;
                if (k < 2) problems.Add("A matching question needs at least 2 pairs.");
                else if (k != v) problems.Add($"Matching has {k} keys but {v} values — they must pair up.");
                break;
            case GameMode.Enumerate:
                if ((q.Enumerate?.Groups.Count ?? 0) < 2)
                    problems.Add("An enumeration question needs at least 2 answers.");
                break;
            default:
                var filled = q.Options.Where(o => !string.IsNullOrWhiteSpace(o)).ToList();
                if (filled.Count < 2) problems.Add("Give the question at least two answer choices.");
                else if (filled.Select(o => o.ToLowerInvariant()).Distinct().Count() != filled.Count)
                    problems.Add("Two choices are identical — a player could be right and marked wrong.");
                if (string.IsNullOrWhiteSpace(q.CorrectAnswer)) problems.Add("Pick which choice is correct.");
                break;
        }
        return problems;
    }

    /// A blank hand-authored question for a round of `format`.
    public static Question Blank(GameMode format, string categoryId) => new()
    {
        Id = Guid.NewGuid().ToString("N"),
        Prompt = "",
        Options = format switch
        {
            GameMode.TypeAnswer or GameMode.ClosestCall or GameMode.Ordering
                or GameMode.Matching or GameMode.Enumerate => [""],
            _ => ["", "", "", ""],
        },
        CorrectIndex = 0,
        CategoryId = categoryId,
        Difficulty = 3,
        TemplateId = "hand",
    };
}
