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
        Background = new SolidColorBrush(Color.Parse("#0A0A12"));
        Width = 1280;
        Height = 720;
        ShowInTaskbar = true;   // §6.3a: it is a real second window, not a takeover
        Content = new ProjectorView { DataContext = vm };
        // Esc always returns from fullscreen. A chromeless fullscreen window with no way
        // out is a trap mid-night, and it is the one state a host cannot click out of.
        KeyDown += (_, e) =>
        {
            if (e.Key != Avalonia.Input.Key.Escape) return;
            if (WindowState == WindowState.FullScreen) ExitFullScreen();
            else Close();
            e.Handled = true;
        };
    }

    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        PlaceOnProjector();
        if (Screens is { } s) s.Changed += (_, _) => PlaceOnProjector();
    }

    /// Go chromeless-fullscreen on a real second display. With only ONE monitor, stay a
    /// normal decorated window instead (§6.3a): fullscreen on the primary would bury the
    /// cockpit under an undecorated window with no title bar and no taskbar affordance,
    /// which reads as the projector "not opening as a separate window" at all.
    private void PlaceOnProjector()
    {
        var screens = Screens;
        if (screens is null || screens.All.Count == 0) return;
        var target = screens.All.FirstOrDefault(sc => !sc.IsPrimary);
        if (target is null)
        {
            ExitFullScreen();
            return;
        }
        WindowDecorations = Avalonia.Controls.WindowDecorations.None; // chromeless (Avalonia 12)
        WindowState = WindowState.Normal;
        Position = target.Bounds.Position;  // physical px — set BEFORE FullScreen
        WindowState = WindowState.FullScreen;
    }

    /// The single-monitor (and unplugged-projector) shape: a normal window the host can
    /// drag onto the projector, resize, and close like anything else.
    private void ExitFullScreen()
    {
        WindowState = WindowState.Normal;
        WindowDecorations = Avalonia.Controls.WindowDecorations.Full;
    }
}
