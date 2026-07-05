using System;
using System.ComponentModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Store;

namespace Tidbits.App.ViewModels;

/// Wraps a GameEngine for the UI: owns the 100ms tick timer (on the UI thread, so
/// Core stays timer-free), records the game when it finishes, and exposes the engine
/// for binding + the game actions.
public sealed class GameViewModel : ObservableObject, IDisposable
{
    public GameEngine Engine { get; }
    private readonly DispatcherTimer _timer;
    private readonly RecordsStore? _records;
    private bool _recorded;

    /// Raised when the player quits back to the Play surface.
    public event Action? Closed;

    public GameViewModel(GameEngine engine, RecordsStore? records = null)
    {
        Engine = engine;
        _records = records;
        Engine.PropertyChanged += OnEngineChanged;
        _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Normal,
            (_, _) => Engine.Tick());
        _timer.Start();
    }

    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (Engine.CurrentPhase == GameEngine.Phase.Finished && !_recorded)
        {
            _recorded = true;
            _records?.Record(Engine.Summary);
        }
    }

    public void Submit(int index) => Engine.Submit(index);
    public void Advance() => Engine.Advance();
    public void Quit() { Engine.Quit(); Closed?.Invoke(); }

    public void Dispose()
    {
        _timer.Stop();
        Engine.PropertyChanged -= OnEngineChanged;
    }
}
