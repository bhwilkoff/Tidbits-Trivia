using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.Core.Networking;

/// The cross-platform Trivia Night host — a lightweight game master over the same
/// live/{code} RTDB backend as Tidbits Live. Builds the night, opens a room, publishes
/// each question with the answer withheld until reveal, auto-scores on reveal, paces
/// Reveal → Next. Port of LiveNightHost.swift. ObservableObject so the cockpit binds;
/// LiveHostNet.Changed (off-thread) is relayed — the UI marshals.
public sealed class LiveNightHost : ObservableObject
{
    public enum Stage { Lobby, Playing, Ended }

    public LiveHostNet Net { get; }
    private readonly QuestionProvider _provider;
    private readonly NightPlan _plan;
    private readonly TriviaCategory _category;

    public string Title { get; }
    public Stage CurrentStage { get; private set; } = Stage.Lobby;
    public List<Question> Questions { get; private set; } = new();
    public int Index { get; private set; }
    public bool Revealed { get; private set; }
    public bool Opening { get; private set; }
    public string? ErrorText { get; private set; }

    public int PointsPerCorrect { get; set; } = 1;
    public bool HostPlays { get; set; }
    public string HostName { get; set; } = "Host";
    public bool SpeedBonus { get; set; }
    public string? FastestUid { get; private set; }
    public bool Locked { get; private set; }
    public int? HostChoice { get; private set; }
    public bool HostAnswered => HostChoice is not null;

    private List<string> _shuffledOrder = new();
    private List<string> _shuffledValues = new();

    public LiveNightHost(NightPlan plan, TriviaCategory category, QuestionProvider provider,
                         string title = "Trivia Night", LiveHostNet? net = null)
    {
        _plan = plan; _category = category; _provider = provider; Title = title;
        Net = net ?? new LiveHostNet();
        Net.Changed += Notify;
    }

    private void Notify() => OnPropertyChanged(string.Empty);

    // Read-model
    public string Code => Net.Code;
    public bool IsOpen => Net.IsOpen;
    public Question? Current => Index >= 0 && Index < Questions.Count ? Questions[Index] : null;
    public IReadOnlyList<LiveHostNet.Joined> Standings => Net.JoinedList();
    public int PlayerCount => Net.PlayerCount;
    public int AnsweredCount => Net.AnsweredCount;
    public int RoundIndex => Current?.RoundIndex ?? 0;
    public int RoundNumber => RoundIndex + 1;
    public int RoundCount => Math.Max(_plan.Rounds.Count, 1);
    public string RoundTitle => RoundIndex < _plan.Rounds.Count ? _plan.Rounds[RoundIndex].Kind.NightRoundTitle() : "";

    /// Live per-option answer counts for the current MCQ (empty for non-MCQ) —
    /// updates as submissions stream in (3.20). Index-aligned with the options.
    public IReadOnlyList<int> AnswerDistribution
    {
        get
        {
            var q = Current;
            if (q is null || !LiveScoring.IsMcq(q)) return System.Array.Empty<int>();
            return Tally(q.Options.Count, Net.AnswersSnapshot().Values.Select(a => a.Choice));
        }
    }

    /// Count choices into per-option buckets (out-of-range choices ignored). Pure
    /// so the tally can be unit-tested without a live room.
    public static int[] Tally(int optionCount, IEnumerable<int?> choices)
    {
        var counts = new int[System.Math.Max(0, optionCount)];
        foreach (var c in choices)
            if (c is { } i && i >= 0 && i < counts.Length) counts[i]++;
        return counts;
    }

    public (int N, int Of) QuestionInRound
    {
        get
        {
            var inRound = Questions.Select((q, i) => (q, i)).Where(x => x.q.RoundIndex == RoundIndex).ToList();
            var pos = inRound.FindIndex(x => x.i == Index);
            return (pos + 1, inRound.Count);
        }
    }

    // Lifecycle / pacing
    public async Task OpenRoom()
    {
        if (Net.IsOpen || Opening) return;
        Opening = true; ErrorText = null; Notify();
        if (await Net.Open(Title) is null) ErrorText = "Couldn't open a room. Check your connection.";
        Opening = false; Notify();
    }

    public async Task Start()
    {
        if (!Net.IsOpen) await OpenRoom();
        if (!Net.IsOpen) return;
        Questions = await _provider.NightQuestions(_plan, _category);
        if (Questions.Count == 0) { ErrorText = "No questions available."; Notify(); return; }
        if (HostPlays) await Net.JoinAsHost(string.IsNullOrEmpty(HostName) ? "Host" : HostName);
        Index = 0; Revealed = false; HostChoice = null; Locked = false; CurrentStage = Stage.Playing;
        PrepareQuestion();
        await Net.SetState("live");
        await Net.Publish(BuildPub());
        Notify();
    }

    private void PrepareQuestion()
    {
        _shuffledOrder = Current?.Ordering is { } o ? QueryHelpers.Shuffle(o.ToList()) : new();
        _shuffledValues = Current?.Matching is { } m ? QueryHelpers.Shuffle(m.Values.ToList()) : new();
    }

    public async Task HostAnswer(int i)
    {
        if (!HostPlays || CurrentStage != Stage.Playing || Revealed || HostChoice is not null || Current is not { } q) return;
        HostChoice = i;
        await Net.SubmitHostAnswer(LiveRoom.Qid(q.RoundIndex ?? 0, Index), i);
        Notify();
    }

    public async Task Lock()
    {
        if (CurrentStage != Stage.Playing || Revealed || Locked) return;
        Locked = true;
        await Net.Publish(BuildPub());
        Notify();
    }

    public async Task Reveal()
    {
        if (CurrentStage != Stage.Playing || Current is null || Revealed) return;
        Revealed = true;
        await Net.Publish(BuildPub()); // answerIndex now included
        await AutoScore();
        Notify();
    }

    public async Task Next()
    {
        if (CurrentStage != Stage.Playing || !Revealed) return;
        Revealed = false; HostChoice = null; Locked = false;
        Index++;
        if (Current is null) await End();
        else { PrepareQuestion(); await Net.Publish(BuildPub()); }
        Notify();
    }

    /// Skip the current question without revealing or scoring it (show-nav 3.17).
    public async Task SkipNext()
    {
        if (CurrentStage != Stage.Playing) return;
        Revealed = false; HostChoice = null; Locked = false;
        Index++;
        if (Current is null) await End();
        else { PrepareQuestion(); await Net.Publish(BuildPub()); }
        Notify();
    }

    /// Step back to the previous question (unrevealed) — for a misfire or a re-ask.
    public async Task GoBack()
    {
        if (CurrentStage != Stage.Playing || Index <= 0) return;
        Revealed = false; HostChoice = null; Locked = false;
        Index--;
        PrepareQuestion();
        await Net.Publish(BuildPub());
        Notify();
    }

    public bool CanGoBack => CurrentStage == Stage.Playing && Index > 0;

    /// Manual score override (3.18) — nudge a team's score (never below 0).
    public async Task AdjustScore(string uid, int delta)
    {
        if (string.IsNullOrEmpty(uid)) return;
        await Net.SetScore(uid, Math.Max(0, Net.ScoreOf(uid) + delta));
        Notify();
    }

    public async Task End()
    {
        CurrentStage = Stage.Ended;
        await Net.SetState("ended");
        await Net.Publish(EndedPub());
        Notify();
    }

    public Task Close() => Net.Close();

    // Internals
    private LiveRoom.Pub BuildPub()
    {
        var q = Current;
        if (q is null) return EndedPub();
        var inR = QuestionInRound;
        var fmt = RoundIndex < _plan.Rounds.Count ? _plan.Rounds[RoundIndex].Kind.Id() : "";
        var mcq = LiveScoring.IsMcq(q);
        return new LiveRoom.Pub
        {
            Round = RoundNumber, RoundTitle = RoundTitle,
            Qid = LiveRoom.Qid(q.RoundIndex ?? 0, Index),
            QNum = inR.N, QTotal = inR.Of,
            Phase = Revealed ? LiveRoom.Phase.Reveal : LiveRoom.Phase.Question,
            Prompt = q.Prompt, Options = mcq ? q.Options : null, Format = fmt,
            AnswerIndex = Revealed && mcq ? q.CorrectIndex : null,
            ImageUrl = q.ImageUrl,
            Numeric = q.Closest is { } c ? new LiveRoom.Numeric { Min = c.Min, Max = c.Max, Step = c.Step, Unit = c.Unit } : null,
            OrderItems = q.Ordering is not null ? _shuffledOrder : null,
            MatchKeys = q.Matching?.Keys,
            MatchValues = q.Matching is not null ? _shuffledValues : null,
            EnumTarget = q.Enumerate?.Total,
            Locked = Locked && !Revealed ? true : null,
        };
    }

    private LiveRoom.Pub EndedPub() => new()
    {
        Round = RoundNumber, RoundTitle = RoundTitle, Qid = "end", QNum = 0, QTotal = 0,
        Phase = LiveRoom.Phase.Ended, Prompt = "", Format = "",
    };

    /// On reveal, score every submission against the host's local Question, plus a speed bonus.
    private async Task AutoScore()
    {
        var q = Current;
        if (q is null) return;
        var answers = Net.AnswersSnapshot();
        var baseScores = answers.Select(kv =>
            (uid: kv.Key, pts: LiveScoring.Score(q, kv.Value, _shuffledOrder, _shuffledValues, PointsPerCorrect), ts: kv.Value.Ts)).ToList();

        var correctBySpeed = baseScores.Where(e => e.pts > 0).OrderBy(e => e.ts).ToList();
        FastestUid = correctBySpeed.Count > 0 ? correctBySpeed[0].uid : null;

        var bonus = new Dictionary<string, int>();
        if (SpeedBonus)
            for (int rank = 0; rank < correctBySpeed.Count && rank < 3; rank++)
                bonus[correctBySpeed[rank].uid] = 3 - rank; // +3 / +2 / +1

        foreach (var e in baseScores)
        {
            var total = e.pts + bonus.GetValueOrDefault(e.uid);
            if (total > 0) await Net.SetScore(e.uid, Net.ScoreOf(e.uid) + total);
        }
    }
}
