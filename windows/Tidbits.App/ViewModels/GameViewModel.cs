using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
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

    /// Raised once when the game reaches Finished (after the record write) — lets
    /// the launcher log a Daily result, etc.
    public event Action? Finished;

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
    // L5 "how did you know that?": hard questions (difficulty >= 4) the player nailed.
    public IReadOnlyList<AnsweredQuestion> Nailed =>
        Summary.Answered.Where(a => a.IsCorrect && a.Question.Difficulty >= 4).ToList();
    public bool HasNailed => Nailed.Count > 0;

    /// Weak-Spot Arena only: how many true misses this round turned correct — the
    /// payoff headline (docs/CLUB-FEATURES-BUILD.md "Feature 1"). null outside .weakSpot.
    public int? WeakSpotGapsClosed
    {
        get
        {
            if (Engine.Mode != GameMode.WeakSpot) return null;
            var trueMissIds = Engine.WeakSpotReasons
                .Where(kv => kv.Value.StartsWith("Missed", StringComparison.Ordinal))
                .Select(kv => kv.Key).ToHashSet();
            return Summary.Answered.Count(a => a.IsCorrect && trueMissIds.Contains(a.Question.Id));
        }
    }
    public bool HasWeakSpotGapsClosed => WeakSpotGapsClosed is not null;
    public string WeakSpotGapsClosedHeadline =>
        $"You closed {WeakSpotGapsClosed} gap{(WeakSpotGapsClosed == 1 ? "" : "s")}";
    public string WeakSpotGapsClosedSubtitle =>
        (WeakSpotGapsClosed ?? 0) > 0 ? "Turned a miss into a win" : "Nothing to close yet this round";

    /// The conversation-starter share for a nailed question (web/iOS parity).
    public static string HowDidYouKnowText(AnsweredQuestion a) =>
        $"I knew \"{a.Question.Prompt}\" on Tidbits Trivia — it's {a.Question.CorrectAnswer}. How did YOU know that?";
    public bool CanPlayAgain => Summary.Mode != GameMode.Daily;

    // Day-streak surfacing at the results moment (read after the record write).
    public int DayStreak => _records?.Streak.Current ?? 0;
    public bool HasDayStreak => DayStreak >= 1;
    public string DayStreakLine => DayStreak == 1 ? "1 day streak" : $"{DayStreak} day streak";
    public bool IsBestStreak => _records is { } r && r.Streak.Current >= 2 && r.Streak.Current == r.Streak.Best;

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
            Finished?.Invoke();
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
