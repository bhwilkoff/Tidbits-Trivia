using System;
using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.App.ViewModels;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class JoinPlayerView : UserControl
{
    private static readonly IBrush Correct = new SolidColorBrush(Color.Parse("#1E9E6A"));
    private static readonly IBrush Wrong = new SolidColorBrush(Color.Parse("#D64545"));
    private static readonly IBrush Picked = new SolidColorBrush(Color.Parse("#FF5C35"));

    private LivePlayerViewModel? _vm;
    private readonly Avalonia.Threading.DispatcherTimer _tick;
    private Window? _window;

    public JoinPlayerView()
    {
        InitializeComponent();
        _tick = new Avalonia.Threading.DispatcherTimer(
            TimeSpan.FromSeconds(1), Avalonia.Threading.DispatcherPriority.Normal, (_, _) => RefreshCountdown());
        _tick.Start();
        AttachedToVisualTree += (_, _) =>
        {
            // Wave C cheat signal (3.27): if the player switches away from the app
            // while a question is live and unanswered, flag their next answer.
            _window = TopLevel.GetTopLevel(this) as Window;
            if (_window is not null) _window.Deactivated += OnWindowDeactivated;
        };
        DetachedFromVisualTree += (_, _) =>
        {
            _tick.Stop();
            if (_window is not null) _window.Deactivated -= OnWindowDeactivated;
        };
    }

    private void OnWindowDeactivated(object? sender, EventArgs e)
    {
        if (_vm is { } vm && vm.ShowQuestion && !vm.Client.HasAnswered)
            vm.Client.Blurred = true;
    }

    /// Tick the host's countdown down locally (coral, turns urgent ≤5s).
    private void RefreshCountdown()
    {
        var s = _vm?.SecondsRemaining;
        CountdownText.Text = s is { } n and > 0 ? $"{n}s" : "";
        CountdownText.Foreground = s is { } m && m <= 5 ? Wrong : Picked;
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (_vm is not null) _vm.Client.Changed -= OnClientChanged;
        _vm = DataContext as LivePlayerViewModel;
        if (_vm is not null) _vm.Client.Changed += OnClientChanged;
        RebuildOptions();
        RebuildCoplayers();
    }

    private void OnClientChanged() => Avalonia.Threading.Dispatcher.UIThread.Post(() => { RebuildOptions(); RebuildCoplayers(); });

    /// At the wrap, list the people you played with, each with an Add / Added button.
    private void RebuildCoplayers()
    {
        CoplayersPanel.Children.Clear();
        if (_vm is not { } vm || !vm.HasCoplayers) return;
        foreach (var co in vm.Coplayers)
        {
            var friend = co;
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            row.Children.Add(new TextBlock { Text = friend.Name, VerticalAlignment = VerticalAlignment.Center });
            bool added = vm.IsFriend(friend.Uid);
            var btn = new Button
            {
                Content = added ? "Added ✓" : "Add", IsEnabled = !added,
                Padding = new Thickness(14, 6), FontSize = 13,
            };
            btn.Click += (_, _) => { vm.AddFriend(friend); btn.Content = "Added ✓"; btn.IsEnabled = false; };
            Grid.SetColumn(btn, 1);
            row.Children.Add(btn);
            CoplayersPanel.Children.Add(row);
        }
    }

    private async void OnJoin(object? sender, RoutedEventArgs e)
    {
        if (_vm is null) return;
        await _vm.Join(CodeBox.Text ?? "", TeamBox.Text ?? "");
    }

    /// Options: clickable MCQ buttons while answering; on reveal, colored (correct green /
    /// your-wrong-pick red / others dim). After answering, your pick shows in the brand color.
    private void RebuildOptions()
    {
        OptionsPanel.Children.Clear();
        var c = _vm?.Client;
        if (c?.Pub?.Options is not { } opts) return;

        bool question = c.Pub.Phase == LiveRoom.Phase.Question;
        bool reveal = c.Pub.Phase == LiveRoom.Phase.Reveal;
        bool answered = c.HasAnswered;

        // Final wager round: a stake stepper (0…your score) above the options.
        if (question && !answered && _vm is { IsWager: true } vm)
        {
            int max = System.Math.Max(0, vm.MaxWager);
            var label = new TextBlock { Text = $"Wager: {vm.Wager} of {max}", FontWeight = FontWeight.Bold, Margin = new Thickness(0, 0, 0, 4) };
            var stake = new Slider { Minimum = 0, Maximum = max, Value = vm.Wager, IsSnapToTickEnabled = true, TickFrequency = 1 };
            stake.PropertyChanged += (_, ev) =>
            {
                if (ev.Property == Slider.ValueProperty) { vm.Wager = (int)stake.Value; label.Text = $"Wager: {vm.Wager} of {max}"; }
            };
            OptionsPanel.Children.Add(label);
            OptionsPanel.Children.Add(stake);
        }

        for (int i = 0; i < opts.Count; i++)
        {
            int idx = i;
            var btn = new Button
            {
                Content = opts[i],
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(16, 14),
                FontSize = 16,
                Margin = new Thickness(0, 4),
            };

            if (question && !answered)
            {
                btn.Click += (_, _) => _ = _vm!.SubmitChoice(idx);
            }
            else
            {
                btn.IsHitTestVisible = false;
                if (reveal && i == c.Pub.AnswerIndex) { btn.Background = Correct; btn.Foreground = Brushes.White; }
                else if (i == c.Chosen) { btn.Background = reveal ? Wrong : Picked; btn.Foreground = Brushes.White; }
                else btn.Opacity = 0.45;
            }
            OptionsPanel.Children.Add(btn);
        }
    }
}
