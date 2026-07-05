using System;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Store;

namespace Tidbits.App.ViewModels;

/// Wraps a GameEngine for the UI: owns the 100ms tick timer (on the UI thread, so
/// Core stays timer-free) and exposes the engine for binding + the game actions.
public sealed class GameViewModel : ObservableObject, IDisposable
{
    public GameEngine Engine { get; }
    private readonly DispatcherTimer _timer;

    /// Raised when the player quits back to the Play surface.
    public event Action? Closed;

    public GameViewModel(GameEngine engine)
    {
        Engine = engine;
        _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Normal,
            (_, _) => Engine.Tick());
        _timer.Start();
    }

    public void Submit(int index) => Engine.Submit(index);
    public void Advance() => Engine.Advance();
    public void Quit() { Engine.Quit(); Closed?.Invoke(); }

    public void Dispose() => _timer.Stop();
}
