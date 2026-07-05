using System;
using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
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

    /// Options are rebuilt on each engine change so reveal can recolor them
    /// (green correct / red chosen-wrong / dim others) — clickable only while playing.
    private void RebuildOptions()
    {
        OptionsPanel.Children.Clear();
        var engine = _vm?.Engine;
        if (engine?.Current is not { } q) return;
        if (engine.CurrentPhase is not (GameEngine.Phase.Playing or GameEngine.Phase.Reveal)) return;

        bool reveal = engine.CurrentPhase == GameEngine.Phase.Reveal;
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

    private void OnNext(object? sender, RoutedEventArgs e) => _vm?.Advance();

    private void OnDone(object? sender, RoutedEventArgs e) => _vm?.Quit();
}
