using System;
using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.App.ViewModels;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class GameView : UserControl
{
    private static readonly IBrush Correct = new SolidColorBrush(Color.Parse("#1E9E6A"));
    private static readonly IBrush Wrong = new SolidColorBrush(Color.Parse("#D64545"));

    private GameViewModel? _vm;

    public GameView()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (_vm is not null) _vm.Engine.PropertyChanged -= OnEngineChanged;
        _vm = DataContext as GameViewModel;
        if (_vm is not null) _vm.Engine.PropertyChanged += OnEngineChanged;
        RebuildOptions();
    }

    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e) => RebuildOptions();

    /// The answer surface is rebuilt on each engine change and dispatched by the
    /// question's shape: MCQ options (recolored on reveal), a numeric slider
    /// (Closest Call), or a text field (Name It / Type-the-answer).
    private void RebuildOptions()
    {
        OptionsPanel.Children.Clear();
        var engine = _vm?.Engine;
        if (engine?.Current is not { } q) return;
        if (engine.CurrentPhase is not (GameEngine.Phase.Playing or GameEngine.Phase.Reveal)) return;

        bool reveal = engine.CurrentPhase == GameEngine.Phase.Reveal;
        if (q.Closest is { } closest) { BuildNumeric(engine, closest, reveal); return; }
        if (q.Accepted is not null) { BuildText(engine, reveal); return; }
        BuildMcq(engine, q, reveal);
    }

    /// MCQ options — green correct / red chosen-wrong / dim others on reveal.
    private void BuildMcq(GameEngine engine, Tidbits.Core.Models.Question q, bool reveal)
    {
        for (int i = 0; i < q.Options.Count; i++)
        {
            int idx = i;
            var btn = new Button
            {
                Content = q.Options[i],
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(16, 13),
                FontSize = 15,
                Margin = new Thickness(0, 4),
            };
            if (reveal)
            {
                // Non-interactive via hit-test only — NOT IsEnabled=false, whose disabled-state
                // styling would override the green/red backgrounds we set here.
                btn.IsHitTestVisible = false;
                if (i == q.CorrectIndex) { btn.Background = Correct; btn.Foreground = Brushes.White; }
                else if (i == engine.ChosenIndex) { btn.Background = Wrong; btn.Foreground = Brushes.White; }
                else btn.Opacity = 0.45;
            }
            else
            {
                btn.Click += (_, _) => _vm?.Submit(idx);
            }
            OptionsPanel.Children.Add(btn);
        }
    }

    /// Closest Call — a slider over [min,max] plus a live value read-out and a
    /// Submit button. On reveal, shows the player's guess (the answer + points
    /// land in the shared "learn the fact" card).
    private void BuildNumeric(GameEngine engine, Tidbits.Core.Models.ClosestSpec spec, bool reveal)
    {
        string Fmt(double v)
        {
            var n = v == Math.Round(v) ? ((long)v).ToString() : v.ToString("0.##");
            return string.IsNullOrEmpty(spec.Unit) ? n : $"{n} {spec.Unit}";
        }

        if (reveal)
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = $"Your guess: {Fmt(engine.CurrentGuess)}",
                FontSize = 15, Opacity = 0.8, Margin = new Thickness(0, 4),
            });
            return;
        }

        var readout = new TextBlock
        {
            Text = Fmt(engine.CurrentGuess), FontSize = 30, FontWeight = FontWeight.Bold,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8),
        };
        var slider = new Slider
        {
            Minimum = spec.Min, Maximum = spec.Max, Value = engine.CurrentGuess,
            TickFrequency = spec.Step > 0 ? spec.Step : 1, IsSnapToTickEnabled = spec.Step > 0,
            Margin = new Thickness(0, 4),
        };
        slider.PropertyChanged += (_, ev) =>
        {
            if (ev.Property == Slider.ValueProperty)
            {
                engine.SetGuess(slider.Value);
                readout.Text = Fmt(engine.CurrentGuess);
            }
        };
        var ends = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*") };
        var lo = new TextBlock { Text = Fmt(spec.Min), FontSize = 12, Opacity = 0.55 };
        var hi = new TextBlock { Text = Fmt(spec.Max), FontSize = 12, Opacity = 0.55,
            HorizontalAlignment = HorizontalAlignment.Right };
        Grid.SetColumn(hi, 1);
        ends.Children.Add(lo); ends.Children.Add(hi);

        var submit = new Button
        {
            Content = "Submit guess", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        submit.Click += (_, _) => engine.SubmitGuess();

        OptionsPanel.Children.Add(readout);
        OptionsPanel.Children.Add(slider);
        OptionsPanel.Children.Add(ends);
        OptionsPanel.Children.Add(submit);
    }

    /// Name It / Type-the-answer — a text field + Submit (also submits on Enter).
    private void BuildText(GameEngine engine, bool reveal)
    {
        if (reveal)
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(engine.TypedText) ? "You didn't answer" : $"You typed: {engine.TypedText}",
                FontSize = 15, Opacity = 0.8, Margin = new Thickness(0, 4),
            });
            return;
        }

        var box = new TextBox
        {
            Text = engine.TypedText, Watermark = "Type your answer…", FontSize = 16,
            Margin = new Thickness(0, 4),
        };
        var submit = new Button
        {
            Content = "Submit", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        void Go() { engine.TypedText = box.Text ?? ""; engine.SubmitText(); }
        box.TextChanged += (_, _) => engine.TypedText = box.Text ?? "";
        box.KeyDown += (_, ev) => { if (ev.Key == Avalonia.Input.Key.Enter) Go(); };
        submit.Click += (_, _) => Go();

        OptionsPanel.Children.Add(box);
        OptionsPanel.Children.Add(submit);
        box.Focus();
    }

    private void OnNext(object? sender, RoutedEventArgs e) => _vm?.Advance();

    private void OnDone(object? sender, RoutedEventArgs e) => _vm?.Quit();

    private void OnPlayAgain(object? sender, RoutedEventArgs e) => _vm?.PlayAgain();

    /// Copy the spoiler-free share text to the clipboard (Windows has no system
    /// share sheet for arbitrary text; clipboard is the native idiom).
    private async void OnShare(object? sender, RoutedEventArgs e)
    {
        if (_vm is null) return;
        var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
        if (clipboard is null) return;
        await clipboard.SetTextAsync(_vm.ShareString);
        if (ShareButton is { } b) b.Content = "Copied ✓";
    }
}
