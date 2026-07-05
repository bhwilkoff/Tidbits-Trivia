using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Media;
using Tidbits.App.ViewModels;

namespace Tidbits.App.Views;

/// The big-screen projector output (WINDOWS-DESIGN §6.3): a separate chromeless
/// window that goes fullscreen on the SECOND monitor. Survives display hot-plug —
/// on a screen change it re-picks a target and never vanishes off-screen.
public sealed class ProjectorWindow : Window
{
    public ProjectorWindow(LiveHostViewModel vm)
    {
        Title = "Tidbits Live — Projector";
        WindowDecorations = Avalonia.Controls.WindowDecorations.None; // chromeless (Avalonia 12)
        Background = new SolidColorBrush(Color.Parse("#0A0A12"));
        Width = 1280;
        Height = 720;
        Content = new ProjectorView { DataContext = vm };
    }

    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        PlaceOnProjector();
        if (Screens is { } s) s.Changed += (_, _) => PlaceOnProjector();
    }

    /// Position fullscreen on the non-primary display; fall back to the primary if
    /// there's only one (or the projector was unplugged). Set Position BEFORE
    /// FullScreen so it lands on the intended monitor.
    private void PlaceOnProjector()
    {
        var screens = Screens;
        if (screens is null || screens.All.Count == 0) return;
        var target = screens.All.FirstOrDefault(sc => !sc.IsPrimary)
                     ?? screens.Primary
                     ?? screens.All[0];
        WindowState = WindowState.Normal;
        Position = target.Bounds.Position; // physical px
        WindowState = WindowState.FullScreen;
    }
}
