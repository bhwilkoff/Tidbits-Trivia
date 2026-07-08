using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

/// The host audio control center (Wave B): PA output-device routing (3.31), a
/// looping music bed (3.33), and the SFX board (3.30) in one panel. Static builder
/// so it renders from injected state; playback wires to AvPlayer.
public static class AudioPanelUi
{
    public static Control BuildPanel(
        IReadOnlyList<(string Id, string Name)> devices, string? currentDevice, Action<string>? onDevice,
        bool bedPlaying, int bedVolume, Action? onChooseBed, Action? onStopBed, Action<int>? onBedVolume,
        IReadOnlyList<SfxPad> pads, Action<string>? onPlaySfx, Action? onAddSfx, Action<string>? onRemoveSfx)
    {
        var root = new StackPanel { Spacing = 18, MinWidth = 400 };

        // PA output-device routing (3.31)
        var pa = new StackPanel { Spacing = 6 };
        pa.Children.Add(Header("PA output"));
        if (devices.Count == 0)
            pa.Children.Add(new TextBlock { Text = "System default (no other devices detected).", Opacity = 0.6, FontSize = 12 });
        else
        {
            var combo = new ComboBox { ItemsSource = devices.Select(d => d.Name).ToList(), MinWidth = 260 };
            var cur = devices.ToList().FindIndex(d => d.Id == currentDevice);
            combo.SelectedIndex = cur >= 0 ? cur : 0;
            combo.SelectionChanged += (_, _) => { if (combo.SelectedIndex is int i && i >= 0 && i < devices.Count) onDevice?.Invoke(devices[i].Id); };
            pa.Children.Add(combo);
        }
        root.Children.Add(pa);

        // Music bed (3.33)
        var bed = new StackPanel { Spacing = 8 };
        bed.Children.Add(Header("Music bed"));
        var bedRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var choose = new Button { Content = "Choose bed", Padding = new Avalonia.Thickness(14, 8) };
        choose.Click += (_, _) => onChooseBed?.Invoke();
        bedRow.Children.Add(choose);
        var stop = new Button { Content = "Stop", Padding = new Avalonia.Thickness(14, 8), IsEnabled = bedPlaying };
        stop.Click += (_, _) => onStopBed?.Invoke();
        bedRow.Children.Add(stop);
        bed.Children.Add(bedRow);
        var vol = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        vol.Children.Add(new TextBlock { Text = "Volume", VerticalAlignment = VerticalAlignment.Center, Opacity = 0.7 });
        var slider = new Slider { Minimum = 0, Maximum = 100, Value = bedVolume, Width = 220, IsSnapToTickEnabled = true, TickFrequency = 5 };
        slider.PropertyChanged += (_, ev) => { if (ev.Property == Slider.ValueProperty) onBedVolume?.Invoke((int)slider.Value); };
        vol.Children.Add(slider);
        bed.Children.Add(vol);
        root.Children.Add(bed);

        // SFX board (3.30)
        root.Children.Add(SfxBoardUi.BuildPanel(pads, onPlaySfx, onAddSfx, onRemoveSfx));
        return new ScrollViewer { Content = root, MaxHeight = 560 };
    }

    private static TextBlock Header(string t) => new() { Text = t, FontSize = 16, FontWeight = FontWeight.Bold };
}
