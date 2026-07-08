using System;
using System.Collections.Generic;
using System.ComponentModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Models;
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

    /// Raised when the player taps Play Again (restart same mode + category).
    public event Action? PlayAgainRequested;

    // Results recap (read once the engine reaches Finished; the finish handler
    // raises an all-properties change so these bindings re-evaluate).
    public GameSummary Summary => Engine.Summary;
    public string Headline => ShareText.Headline(Summary);
    public string ModeCategoryLine => $"{Summary.Mode.Title()} · {Summary.Category.Name}";
    public string CorrectLine => $"{Summary.Correct}/{Summary.Total}";
    public string AccuracyLine => $"{(int)Math.Round(Summary.Accuracy * 100)}%";
    public string Grid => ShareText.Grid(Summary);
    public string ShareString => ShareText.Compose(Summary);
    public IReadOnlyList<AnsweredQuestion> Missed => Summary.Missed;
    public bool HasMissed => Missed.Count > 0;
    public bool CanPlayAgain => Summary.Mode != GameMode.Daily;

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
            OnPropertyChanged(string.Empty); // refresh every recap binding at once
        }
    }

    public void Submit(int index) => Engine.Submit(index);
    public void Advance() => Engine.Advance();
    public void StartRound() => Engine.StartRound();
    public void Quit() { Engine.Quit(); Closed?.Invoke(); }
    public void PlayAgain() => PlayAgainRequested?.Invoke();

    public void Dispose()
    {
        _timer.Stop();
        Engine.PropertyChanged -= OnEngineChanged;
    }
}
