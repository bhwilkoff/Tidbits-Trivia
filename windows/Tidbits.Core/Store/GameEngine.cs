using System.Globalization;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Data;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;
using Tidbits.Core.Services;

namespace Tidbits.Core.Store;

/// Drives one game from first question to summary (port of Core/Store/GameEngine.swift).
/// UI-agnostic. The Swift @Observable ticker Task is lifted out: the engine exposes a
/// pure `Tick()` that the UI layer's timer calls on the UI thread, so Core imports no
/// timer/dispatcher. After each mutating action the engine notifies all bindings.
public sealed class GameEngine : ObservableObject
{
    public enum Phase { Idle, Loading, RoundIntro, Playing, Reveal, Finished }

    private readonly QuestionProvider _provider;
    private readonly DifficultyOverlay _difficulty;

    public GameEngine(QuestionProvider provider, DifficultyOverlay difficulty)
    {
        _provider = provider;
        _difficulty = difficulty;
    }

    // Configuration
    public GameMode Mode { get; private set; } = GameMode.Classic;
    public TriviaCategory Category { get; private set; } = TriviaCategory.Named("mixed");
    public string? DailyDay { get; private set; }
    public NightPlan? NightPlan { get; private set; }

    // Live state
    public Phase CurrentPhase { get; private set; } = Phase.Idle;
    public List<Question> Questions { get; private set; } = new();
    public int Index { get; private set; }
    public int Score { get; private set; }
    public int Streak { get; private set; }
    public int MaxStreak { get; private set; }
    public List<AnsweredQuestion> Answered { get; private set; } = new();
    public AnsweredQuestion? LastAnswer { get; private set; }
    public int? ChosenIndex { get; private set; }

    // Networked host-paced night
    public bool HostPaced { get; private set; }
    public bool AwaitingReveal { get; private set; }
    public Action<int, int, bool>? OnLocalAnswer { get; set; }

    // Stake
    public List<StakeTier> StakeTiers { get; private set; } = new();
    public int CurrentStake { get; private set; }
    public Dictionary<int, StakeOutcome> StakeOutcomes { get; private set; } = new();

    // Closest Call
    public double CurrentGuess { get; private set; }
    public int LastGuessPoints { get; private set; }

    // Ordering
    public List<string> CurrentOrder { get; private set; } = new();
    public int LastOrderPoints { get; private set; }

    // Matching
    public List<string> MatchValues { get; private set; } = new();
    public List<int?> MatchAssign { get; private set; } = new();
    public int? MatchSelectedKey { get; private set; }
    public int LastMatchPoints { get; private set; }

    // Type-the-answer
    public string TypedText { get; set; } = "";

    // Enumeration
    public HashSet<int> EnumFilled { get; private set; } = new();
    public List<string> EnumNamed { get; private set; } = new();
    public bool EnumLastHit { get; set; }

    // Clocks
    public double Remaining { get; private set; }
    private double _clockBudget;
    private DateTime _questionStart = DateTime.UtcNow;
    private DateTime? _globalDeadline;
    private bool _triedLoad;
    private int? _introducedRound;

    public Question? Current => Index >= 0 && Index < Questions.Count ? Questions[Index] : null;

    public double Progress
    {
        get
        {
            if (Mode != GameMode.Classic && Mode != GameMode.Daily) return 0;
            return Questions.Count == 0 ? 0 : (double)Index / Questions.Count;
        }
    }

    public bool LoadFailed => CurrentPhase == Phase.Idle && Questions.Count == 0 && _triedLoad;

    private void Changed() => OnPropertyChanged(string.Empty); // re-read all bindings

    // MARK: Trivia Night helpers
    public NightRound? CurrentRound
    {
        get
        {
            var ri = Current?.RoundIndex;
            if (NightPlan is null || ri is null || ri < 0 || ri >= NightPlan.Rounds.Count) return null;
            return NightPlan.Rounds[ri.Value];
        }
    }
    public int CurrentRoundNumber => (Current?.RoundIndex ?? 0) + 1;
    public int RoundCount => NightPlan?.Rounds.Count ?? 0;

    public NightRound? NextRoundAfterCurrent
    {
        get
        {
            var ri = Current?.RoundIndex;
            if (NightPlan is null || ri is null) return null;
            var nextIdx = Index + 1;
            if (nextIdx < 0 || nextIdx >= Questions.Count) return null;
            var nextRi = Questions[nextIdx].RoundIndex;
            if (nextRi is null || nextRi == ri || nextRi < 0 || nextRi >= NightPlan.Rounds.Count) return null;
            return NightPlan.Rounds[nextRi.Value];
        }
    }

    public double DisplayClockBudget =>
        Mode is GameMode.BarTrivia or GameMode.Mix
            ? ShapeBudget(Current)
            : Mode.PerQuestionSeconds() ?? Mode.GlobalClockSeconds() ?? 30;

    // MARK: Lifecycle
    public async Task StartMix(IReadOnlyList<GameMode> modes, TriviaCategory category)
    {
        Mode = GameMode.Mix; Category = category; DailyDay = null;
        CurrentPhase = Phase.Loading; _triedLoad = true; Reset();
        var qs = await _provider.MixQuestions(modes, category, GameMode.Mix.QuestionCount());
        Questions = qs;
        if (qs.Count == 0) { CurrentPhase = Phase.Idle; Changed(); return; }
        BeginQuestion();
    }

    public async Task Start(GameMode mode, TriviaCategory category, IReadOnlyList<Question>? review = null, string? dailyDay = null)
    {
        Mode = mode; Category = category;
        DailyDay = mode == GameMode.Daily ? (dailyDay ?? QuestionProvider.DayKey()) : null;
        CurrentPhase = Phase.Loading; _triedLoad = true; Reset();
        var qs = await _provider.Questions(mode, category, dailyDay);
        if (review is { Count: > 0 }) qs = Weave(qs, review);
        Questions = qs;
        _provider.MarkSeen(qs.Select(q => q.Id));
        if (qs.Count == 0) { CurrentPhase = Phase.Idle; Changed(); return; }
        if (mode.GlobalClockSeconds() is { } global) _globalDeadline = DateTime.UtcNow.AddSeconds(global);
        BeginQuestion();
    }

    public void StartCustom(GameMode mode, TriviaCategory category, IReadOnlyList<Question> questions)
    {
        Mode = mode; Category = category;
        CurrentPhase = Phase.Loading; _triedLoad = true; Reset();
        Questions = questions.ToList();
        _provider.MarkSeen(questions.Select(q => q.Id));
        if (Questions.Count == 0) { CurrentPhase = Phase.Idle; Changed(); return; }
        if (mode.GlobalClockSeconds() is { } global) _globalDeadline = DateTime.UtcNow.AddSeconds(global);
        BeginQuestion();
    }

    public void StartNight(NightPlan plan, TriviaCategory category, IReadOnlyList<Question> questions, bool hostPaced = false)
    {
        Mode = GameMode.BarTrivia; Category = category;
        CurrentPhase = Phase.Loading; _triedLoad = true; Reset();
        HostPaced = hostPaced; NightPlan = plan;
        Questions = questions.ToList();
        _provider.MarkSeen(questions.Select(q => q.Id));
        if (Questions.Count == 0) { CurrentPhase = Phase.Idle; Changed(); return; }
        BeginQuestion();
    }

    private void Reset()
    {
        NightPlan = null; HostPaced = false; AwaitingReveal = false;
        Index = 0; Score = 0; Streak = 0; MaxStreak = 0;
        Answered = new(); LastAnswer = null; ChosenIndex = null; _globalDeadline = null;
        StakeTiers = Mode == GameMode.Stake
            ? GameModeExtensions.StakeBudget.Select(c => new StakeTier { Value = c.Value, Label = c.Label, Remaining = c.Count }).ToList()
            : new();
        CurrentStake = 0; StakeOutcomes = new(); _introducedRound = null;
    }

    private static List<Question> Weave(List<Question> fresh, IReadOnlyList<Question> review)
    {
        var freshIds = fresh.Select(q => q.Id).ToHashSet();
        var inject = review.Where(q => !freshIds.Contains(q.Id)).Take(Math.Max(1, fresh.Count / 4)).ToList();
        if (inject.Count == 0 || fresh.Count <= inject.Count) return fresh;
        var result = fresh.ToList();
        for (int i = 0; i < inject.Count; i++)
        {
            var pos = Math.Min(result.Count - 1, (i + 1) * result.Count / (inject.Count + 1));
            result[pos] = inject[i];
        }
        return result;
    }

    public NightRound? IntroRound
    {
        get
        {
            var ri = Current?.RoundIndex;
            if (ri is null || NightPlan is null || ri < 0 || ri >= NightPlan.Rounds.Count) return null;
            return NightPlan.Rounds[ri.Value];
        }
    }

    public void StartRound()
    {
        if (CurrentPhase != Phase.RoundIntro) return;
        _introducedRound = Current?.RoundIndex;
        BeginQuestion();
    }

    private void BeginQuestion()
    {
        if (Mode == GameMode.BarTrivia && !HostPaced && !DebugHooks.Autopilot
            && Current?.RoundIndex is { } ri && ri != _introducedRound)
        {
            CurrentPhase = Phase.RoundIntro;
            Changed();
            return;
        }
        ChosenIndex = null; CurrentStake = 0;
        if (Current?.Closest is { } spec) CurrentGuess = Math.Round((spec.Min + spec.Max) / 2);
        if (Current?.Ordering is { } order) CurrentOrder = ShuffledDistinct(order);
        if (Current?.Matching is { } m)
        {
            MatchValues = ShuffledDistinct(m.Values);
            MatchAssign = Enumerable.Repeat((int?)null, m.Keys.Count).ToList();
            MatchSelectedKey = null;
        }
        if (Current?.Accepted is not null) TypedText = "";
        if (Current?.Enumerate is not null) { EnumFilled = new(); EnumNamed = new(); EnumLastHit = false; TypedText = ""; }
        AwaitingReveal = false;
        CurrentPhase = Phase.Playing;
        _questionStart = DateTime.UtcNow;
        _clockBudget = Mode is GameMode.BarTrivia or GameMode.Mix
            ? ShapeBudget(Current)
            : (Mode.PerQuestionSeconds() ?? (GlobalRemaining() ?? 30));
        Remaining = GlobalRemaining() ?? _clockBudget;
        Changed();
    }

    public static double ShapeBudget(Question? q)
    {
        if (q is null) return 25;
        if (q.Enumerate is not null) return 60;
        if (q.Matching is not null) return 40;
        if (q.Ordering is not null) return 35;
        if (q.Closest is not null) return 25;
        if (q.Accepted is not null) return 25;
        if (q.ImageUrl is not null) return 22;
        return 20;
    }

    private double? GlobalRemaining() =>
        _globalDeadline is { } d ? Math.Max(0, (d - DateTime.UtcNow).TotalSeconds) : null;

    /// Called by the UI's timer (~every 100ms) on the UI thread — advances the clock.
    public void Tick()
    {
        if (CurrentPhase != Phase.Playing) return;
        if (GlobalRemaining() is { } g)
        {
            Remaining = g;
            if (g <= 0) { EndGame(); return; }
            OnPropertyChanged(nameof(Remaining));
        }
        else
        {
            var elapsed = (DateTime.UtcNow - _questionStart).TotalSeconds;
            Remaining = Math.Max(0, _clockBudget - elapsed);
            if (Remaining <= 0) ForceTimeoutSubmit();
            else OnPropertyChanged(nameof(Remaining));
        }
    }

    // MARK: Stake
    public void SetStake(int value)
    {
        if (Mode != GameMode.Stake || CurrentPhase != Phase.Playing) return;
        var tier = StakeTiers.FirstOrDefault(t => t.Value == value);
        if (tier is null || tier.Remaining <= 0) return;
        if (CurrentStake != 0)
        {
            var prev = StakeTiers.FirstOrDefault(t => t.Value == CurrentStake);
            if (prev is not null) prev.Remaining += 1;
        }
        tier.Remaining -= 1;
        CurrentStake = value;
        Changed();
    }

    public string StakeLabel => StakeTiers.FirstOrDefault(t => t.Value == CurrentStake)?.Label ?? "";

    // MARK: Closest Call
    public void SetGuess(double value)
    {
        if (CurrentPhase != Phase.Playing || Current?.Closest is not { } spec) return;
        CurrentGuess = Math.Min(spec.Max, Math.Max(spec.Min, value));
        OnPropertyChanged(nameof(CurrentGuess));
    }

    public void SubmitGuess()
    {
        if (CurrentPhase != Phase.Playing || Current is not { Closest: { } spec } q) return;
        var pts = spec.Points(CurrentGuess);
        var close = spec.IsClose(CurrentGuess);
        LastGuessPoints = pts;
        var taken = (DateTime.UtcNow - _questionStart).TotalSeconds;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = close ? 0 : 1, SecondsTaken = taken };
        Answered.Add(answer); LastAnswer = answer;
        if (close) { Streak += 1; MaxStreak = Math.Max(MaxStreak, Streak); Haptics.Correct(); }
        else { Streak = 0; Haptics.Wrong(); }
        Score += pts;
        FinishReveal();
    }

    // MARK: Ordering
    private static List<string> ShuffledDistinct(IReadOnlyList<string> order)
    {
        if (order.Count <= 1) return order.ToList();
        var s = order.ToList();
        for (int i = 0; i < 6; i++) { QueryHelpers.Shuffle(s); if (!s.SequenceEqual(order)) break; }
        return s;
    }

    public void MoveOrderItem(int index, bool up)
    {
        if (CurrentPhase != Phase.Playing || Current?.Ordering is null) return;
        if (index < 0 || index >= CurrentOrder.Count) return;
        var target = up ? index - 1 : index + 1;
        if (target < 0 || target >= CurrentOrder.Count) return;
        (CurrentOrder[index], CurrentOrder[target]) = (CurrentOrder[target], CurrentOrder[index]);
        OnPropertyChanged(nameof(CurrentOrder));
    }

    public void SubmitOrder()
    {
        if (CurrentPhase != Phase.Playing || Current is not { Ordering: { } correct } q) return;
        var rank = new Dictionary<string, int>();
        for (int i = 0; i < correct.Count; i++) rank[correct[i]] = i;
        int inversions = 0;
        for (int i = 0; i < CurrentOrder.Count; i++)
            for (int j = i + 1; j < CurrentOrder.Count; j++)
                if (rank.TryGetValue(CurrentOrder[i], out var a) && rank.TryGetValue(CurrentOrder[j], out var b) && a > b)
                    inversions++;
        var maxInv = correct.Count * (correct.Count - 1) / 2;
        var pts = maxInv == 0 ? 0 : (int)Math.Round(40.0 * (1 - (double)inversions / maxInv));
        LastOrderPoints = pts;
        var perfect = inversions == 0;
        var taken = (DateTime.UtcNow - _questionStart).TotalSeconds;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = perfect ? 0 : 1, SecondsTaken = taken };
        Answered.Add(answer); LastAnswer = answer;
        if (perfect) { Streak += 1; MaxStreak = Math.Max(MaxStreak, Streak); Haptics.Correct(); }
        else { Streak = 0; Haptics.Wrong(); }
        Score += pts;
        FinishReveal();
    }

    // MARK: Matching
    public void SelectMatchKey(int keyIndex)
    {
        if (CurrentPhase != Phase.Playing || Current?.Matching is null) return;
        MatchSelectedKey = MatchSelectedKey == keyIndex ? null : keyIndex;
        OnPropertyChanged(nameof(MatchSelectedKey));
    }

    public void AssignMatchValue(int valueIndex)
    {
        if (CurrentPhase != Phase.Playing || Current?.Matching is null || MatchSelectedKey is not { } key) return;
        if (key < 0 || key >= MatchAssign.Count) return;
        for (int i = 0; i < MatchAssign.Count; i++) if (MatchAssign[i] == valueIndex) MatchAssign[i] = null;
        MatchAssign[key] = valueIndex;
        MatchSelectedKey = null;
        Changed();
    }

    public string? MatchedValue(int keyIndex)
    {
        if (keyIndex < 0 || keyIndex >= MatchAssign.Count || MatchAssign[keyIndex] is not { } v
            || v < 0 || v >= MatchValues.Count) return null;
        return MatchValues[v];
    }

    public void SubmitMatch()
    {
        if (CurrentPhase != Phase.Playing || Current is not { Matching: { } m } q) return;
        int correct = 0;
        for (int k = 0; k < m.Keys.Count; k++) if (MatchedValue(k) == m.Values[k]) correct++;
        var pts = m.Keys.Count == 0 ? 0 : (int)Math.Round(40.0 * correct / m.Keys.Count);
        LastMatchPoints = pts;
        var perfect = correct == m.Keys.Count;
        var taken = (DateTime.UtcNow - _questionStart).TotalSeconds;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = perfect ? 0 : 1, SecondsTaken = taken };
        Answered.Add(answer); LastAnswer = answer;
        if (perfect) { Streak += 1; MaxStreak = Math.Max(MaxStreak, Streak); Haptics.Correct(); }
        else { Streak = 0; Haptics.Wrong(); }
        Score += pts;
        FinishReveal();
    }

    // MARK: Type-the-answer
    public void SubmitText()
    {
        if (Current?.Accepted is not { } acc) return;
        ResolveTyped(MatchesAccepted(TypedText, acc));
    }

    public void MarkTyped(bool correct)
    {
        if (Current?.Accepted is null) return;
        ResolveTyped(correct);
    }

    private void ResolveTyped(bool correct)
    {
        if (CurrentPhase != Phase.Playing || Current is not { } q) return;
        var taken = (DateTime.UtcNow - _questionStart).TotalSeconds;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = correct ? 0 : 1, SecondsTaken = taken };
        Answered.Add(answer); LastAnswer = answer;
        if (correct)
        {
            Streak += 1; MaxStreak = Math.Max(MaxStreak, Streak);
            Score += Scoring.Points(true, taken, Mode.PerQuestionSeconds() ?? 25, Streak);
            Haptics.Correct();
        }
        else { Streak = 0; Haptics.Wrong(); }
        FinishReveal();
    }

    // MARK: Enumeration
    public bool SubmitEnumGuess(string text)
    {
        if (CurrentPhase != Phase.Playing || Current?.Enumerate is not { } spec) return false;
        TypedText = "";
        var n = NormalizeType(text);
        if (n.Length == 0) { EnumLastHit = false; return false; }
        for (int i = 0; i < spec.Groups.Count; i++)
        {
            if (EnumFilled.Contains(i)) continue;
            if (spec.Groups[i].Any(g => NormalizeType(g) == n))
            {
                EnumFilled.Add(i);
                EnumNamed.Add(spec.Groups[i].Count > 0 ? spec.Groups[i][0] : "");
                Score += 1; EnumLastHit = true; Haptics.Correct();
                if (EnumFilled.Count == spec.Groups.Count) FinishEnum();
                else Changed();
                return true;
            }
        }
        EnumLastHit = false; Haptics.Wrong(); Changed();
        return false;
    }

    public void SelfMarkEnum(int count)
    {
        if (CurrentPhase != Phase.Playing || Current?.Enumerate is not { } spec) return;
        var c = Math.Min(Math.Max(0, count), spec.Groups.Count);
        EnumFilled = Enumerable.Range(0, c).ToHashSet();
        EnumNamed = spec.DisplayNames.Take(c).ToList();
        Score += c;
        FinishEnum();
    }

    public void FinishEnum()
    {
        if (CurrentPhase != Phase.Playing || Current is not { Enumerate: { } spec } q) return;
        var got = EnumFilled.Count;
        var hit = got > 0 && got * 2 >= spec.Total;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = hit ? 0 : 1, SecondsTaken = _clockBudget - Remaining };
        Answered.Add(answer); LastAnswer = answer;
        FinishReveal();
    }

    public static bool MatchesAccepted(string input, IReadOnlyList<string> accepted)
    {
        var n = NormalizeType(input);
        if (n.Length == 0) return false;
        return accepted.Any(a => NormalizeType(a) == n);
    }

    /// Fold diacritics, lowercase, keep Unicode alphanumerics + spaces, collapse runs,
    /// drop a leading "the ". Mirrors Swift's normalizeType.
    public static string NormalizeType(string s)
    {
        var folded = RemoveDiacritics(s).ToLowerInvariant();
        var parts = System.Text.RegularExpressions.Regex.Split(folded, @"[^\p{L}\p{N}]+").Where(p => p.Length > 0);
        var t = string.Join(" ", parts);
        if (t.StartsWith("the ", StringComparison.Ordinal)) t = t[4..];
        return t;
    }

    private static string RemoveDiacritics(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(normalized.Length);
        foreach (var c in normalized)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    // MARK: Answering (MCQ)
    public void Submit(int? choice)
    {
        if (CurrentPhase != Phase.Playing || Current is not { } q) return;
        if (Mode == GameMode.Stake && CurrentStake == 0 && choice is not null) return;
        ChosenIndex = choice;
        var taken = (DateTime.UtcNow - _questionStart).TotalSeconds;
        var answer = new AnsweredQuestion { Question = q, ChosenIndex = choice, SecondsTaken = taken };
        Answered.Add(answer); LastAnswer = answer;

        if (Mode == GameMode.Stake && CurrentStake != 0)
        {
            var o = StakeOutcomes.GetValueOrDefault(CurrentStake);
            o.Total += 1;
            if (answer.IsCorrect) o.Hits += 1;
            StakeOutcomes[CurrentStake] = o;
        }

        if (answer.IsCorrect)
        {
            Streak += 1; MaxStreak = Math.Max(MaxStreak, Streak);
            switch (Mode)
            {
                case GameMode.Stake: Score += CurrentStake; break;
                case GameMode.Sweep: Score += 1; break;
                case GameMode.Ladder:
                    var d = _difficulty.DifficultyFor(q);
                    Score += Scoring.Points(true, taken, Mode.PerQuestionSeconds() ?? _clockBudget, Streak) + (d - 1) * 10;
                    break;
                default:
                    Score += Scoring.Points(true, taken, Mode.PerQuestionSeconds() ?? _clockBudget, Streak);
                    break;
            }
            Haptics.Correct();
        }
        else
        {
            Streak = 0; Haptics.Wrong();
            if (Mode == GameMode.Survival) { CurrentPhase = Phase.Reveal; Changed(); return; }
        }
        FinishReveal();
    }

    private void FinishReveal()
    {
        if (HostPaced)
        {
            AwaitingReveal = true;
            if (LastAnswer is { } a) OnLocalAnswer?.Invoke(Index, Score, a.IsCorrect);
        }
        CurrentPhase = Phase.Reveal;
        Changed();
    }

    public void ReleaseReveal()
    {
        if (!HostPaced) return;
        if (CurrentPhase == Phase.Playing) ForceTimeoutSubmit();
        AwaitingReveal = false;
        Changed();
    }

    public void GoToQuestion(int i)
    {
        if (i < 0 || i >= Questions.Count) { EndGame(); return; }
        Index = i;
        BeginQuestion();
    }

    public void FinishExternally() => EndGame();

    private void ForceTimeoutSubmit()
    {
        if (Current?.Closest is not null) SubmitGuess();
        else if (Current?.Ordering is not null) SubmitOrder();
        else if (Current?.Matching is not null) SubmitMatch();
        else if (Current?.Accepted is not null) SubmitText();
        else if (Current?.Enumerate is not null) FinishEnum();
        else Submit(null);
    }

    public void Advance()
    {
        if (Mode == GameMode.Survival && LastAnswer is { IsCorrect: false }) { EndGame(); return; }
        if (GlobalRemaining() is { } g && g <= 0) { EndGame(); return; }
        Index += 1;
        if (Index >= Questions.Count) { EndGame(); return; }
        BeginQuestion();
    }

    private void EndGame()
    {
        CurrentPhase = Phase.Finished;
        Changed();
    }

    public void Quit()
    {
        CurrentPhase = Phase.Idle;
        Reset();
        Questions = new();
        Changed();
    }

    // MARK: Summary
    public GameSummary Summary => new()
    {
        Mode = Mode, Category = Category, Score = Score,
        Correct = Answered.Count(a => a.IsCorrect), Total = Answered.Count, MaxStreak = MaxStreak,
        Answered = Answered.ToList(), StakeOutcomes = new Dictionary<int, StakeOutcome>(StakeOutcomes), DailyDay = DailyDay,
    };
}
