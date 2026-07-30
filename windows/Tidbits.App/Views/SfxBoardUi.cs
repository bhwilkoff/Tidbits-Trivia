using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

/// The host SFX board (3.30): a grid of tap-to-fire sound pads + "Add sound".
/// Static builder so it renders from injected pads in a headless test; playback
/// wires to AvPlayer.PlaySfx separately.
public static class SfxBoardUi
{
    public static Control BuildPanel(IReadOnlyList<SfxPad> pads,
        Action<string>? onPlay = null, Action? onAdd = null, Action<string>? onRemove = null)
    {
        var root = new StackPanel { Spacing = 12, MinWidth = 380 };
        root.Children.Add(new TextBlock { Text = "Sound board", FontSize = 18, FontWeight = FontWeight.Bold });

        if (pads.Count == 0)
            root.Children.Add(new TextBlock { Text = "No sounds yet — add applause, a buzzer, a drumroll…", Opacity = 0.65, TextWrapping = TextWrapping.Wrap });

        var grid = new WrapPanel();
        foreach (var p in pads)
        {
            var pad = p;
            var pill = new Border
            {
                Background = new SolidColorBrush(Color.Parse("#1AFF5C35")),
                CornerRadius = new Avalonia.CornerRadius(12), Margin = new Avalonia.Thickness(0, 0, 8, 8),
            };
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            var play = new Button
            {
                Content = "▶ " + pad.Label, Padding = new Avalonia.Thickness(16, 10),
                Background = Brushes.Transparent, FontWeight = FontWeight.SemiBold,
            };
            play.Click += (_, _) => onPlay?.Invoke(pad.Path);
            row.Children.Add(play);
            var del = new Button { Content = "×", Padding = new Avalonia.Thickness(8, 10), Background = Brushes.Transparent, Opacity = 0.6 };
            Avalonia.Automation.AutomationProperties.SetName(del, $"Remove sound {pad.Label}");
            del.Click += (_, _) => onRemove?.Invoke(pad.Path);
            row.Children.Add(del);
            pill.Child = row;
            grid.Children.Add(pill);
        }
        root.Children.Add(grid);

        var add = new Button { Content = "+ Add sound", Padding = new Avalonia.Thickness(16, 10) };
        add.Click += (_, _) => onAdd?.Invoke();
        root.Children.Add(add);
        return root;
    }
}
