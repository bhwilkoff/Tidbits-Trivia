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
    // Club Marathon only (docs/CLUB-FEATURES-BUILD.md "Feature 3"): the run this
    // session is persisting into, and how many of Engine.Answered have already been
    // forwarded to it (so a re-fired PropertyChanged never double-records an answer).
    private readonly MarathonRun? _marathonRun;
    private int _marathonPersisted;
    // Club Expedition only (docs/CLUB-FEATURES-BUILD.md "Feature 5"): the campaign +
    // stage this session is playing, if any. Unlike Marathon, a stage writes a NORMAL
    // GameRecord via the generic path below — this only adds the campaign-tracking
    // (pass/fail + certificate) on top, once, at Finished.
    private readonly (Expedition Expedition, int StageIndex)? _expeditionStage;

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

    /// Club Marathon only: true while this session is playing/resuming a run —
    /// gates the dedicated scorecard in GameView. The generic recap above reads
    /// `Engine.Summary`, which is only THIS session's slice — wrong for a run
    /// that may span many sessions (docs/CLUB-FEATURES-BUILD.md "Feature 3").
    public bool IsMarathonRun => Engine.Mode == GameMode.Marathon;

    /// The just-completed run's permanent scorecard — set once, the instant the
    /// run reaches its true end (which may be many sessions after it started).
    /// Null until then.
    public MarathonScore? MarathonResult { get; private set; }

    /// Club Expedition only: true while this session is playing one campaign's stage
    /// — gates the dedicated pass/fail/certificate recap in GameView instead of the
    /// generic session-scoped recap (docs/CLUB-FEATURES-BUILD.md "Feature 5").
    public bool IsExpeditionStage => _expeditionStage is not null;

    /// The just-finished stage's outcome — set once, the instant the round reaches
    /// Finished. Null until then / outside an Expedition session.
    public ExpeditionPlayResult? ExpeditionResult { get; private set; }

    /// True for the generic session-scoped recap panel — every session EXCEPT a
    /// Marathon run (its own permanent scorecard) or an Expedition stage (its own
    /// pass/fail/certificate beat), which are mutually exclusive with each other.
    public bool ShowGenericRecap => !IsMarathonRun && !IsExpeditionStage;

    /// The RecordsStore this session actually persists into — GameView reads
    /// this (not a global singleton) for the Marathon scorecard's "vs your last
    /// run" comparison and history count, so it stays correct against whatever
    /// store the caller constructed this ViewModel with (tests included).
    public RecordsStore? Records => _records;

    /// The conversation-starter share for a nailed question (web/iOS parity).
    public static string HowDidYouKnowText(AnsweredQuestion a) =>
        $"I knew \"{a.Question.Prompt}\" on Tidbits Trivia — it's {a.Question.CorrectAnswer}. How did YOU know that?";
    public bool CanPlayAgain => Summary.Mode != GameMode.Daily;

    // Day-streak surfacing at the results moment (read after the record write).
    public int DayStreak => _records?.Streak.Current ?? 0;
    public bool HasDayStreak => DayStreak >= 1;
    public string DayStreakLine => DayStreak == 1 ? "1 day streak" : $"{DayStreak} day streak";
    public bool IsBestStreak => _records is { } r && r.Streak.Current >= 2 && r.Streak.Current == r.Streak.Best;

    /// `marathonRun` is non-null only for a Club Marathon session — it's the run
    /// this session persists every answer into (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 3"). Passing `records` alongside it is required (Marathon still
    /// needs RecordsStore to persist the run/score); Marathon itself writes NO
    /// GameRecord / miss / seen-story via the generic path below.
    public GameViewModel(GameEngine engine, RecordsStore? records = null, MarathonRun? marathonRun = null,
        (Expedition Expedition, int StageIndex)? expeditionStage = null)
    {
        Engine = engine;
        _records = records;
        _marathonRun = marathonRun;
        _expeditionStage = expeditionStage;
        Engine.PropertyChanged += OnEngineChanged;
        _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Normal,
            (_, _) => Engine.Tick());
        _timer.Start();
    }

    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_marathonRun is { } run && _records is { } records)
        {
            // Persist every new answer immediately — a crash/quit never loses
            // progress, the whole point of Marathon.
            while (_marathonPersisted < Engine.Answered.Count)
            {
                Marathon.Record(records, run, Engine.Answered[_marathonPersisted]);
                _marathonPersisted++;
            }
            // The run just reached its true end — write the permanent score and
            // clear the in-progress run. Deliberately skips the generic
            // `_records.Record(Engine.Summary)` path below: Marathon writes NO
            // GameRecord / miss / seen-story (a partial session slice would
            // misreport lifetime stats).
            if (!_recorded && run.CurrentIndex >= run.Total)
            {
                _recorded = true;
                MarathonResult = Marathon.Finish(records, run);
                OnPropertyChanged(string.Empty);
                Finished?.Invoke();
            }
            return;
        }

        if (Engine.CurrentPhase == GameEngine.Phase.Finished && !_recorded)
        {
            _recorded = true;
            _records?.Record(Engine.Summary);
            // Club Expedition (Feature 5): unlike Marathon, a stage IS a normal
            // GameRecord write (above) — this only layers the campaign tracking
            // (pass/fail, next-stage unlock, certificate) on top.
            if (_expeditionStage is { } es && _records is { } expRecords)
            {
                var stage = es.Expedition.Stages.First(s => s.Index == es.StageIndex);
                var (passed, cert) = Expeditions.RecordStageResult(
                    expRecords, es.Expedition, es.StageIndex, Engine.Summary.Correct, Engine.Summary.Total);
                ExpeditionResult = new ExpeditionPlayResult(es.Expedition, stage, passed, Engine.Summary.Correct, Engine.Summary.Total, cert);
            }
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

/// One Expedition stage's just-finished outcome — the recap DTO `GameView` renders
/// via `ExpeditionsUi.BuildStageResult` (docs/CLUB-FEATURES-BUILD.md "Feature 5").
public sealed record ExpeditionPlayResult(
    Expedition Expedition, ExpeditionStage Stage, bool Passed, int Correct, int Total, ExpeditionCertificate? Certificate);
