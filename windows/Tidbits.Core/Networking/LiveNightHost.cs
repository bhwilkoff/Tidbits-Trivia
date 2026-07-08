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
    public int? WagerRoundIndex { get; set; } // Wave A: which round is the final wager (RoundIndex), null = none
    public IReadOnlyList<string> RoundNotes { get; set; } = new List<string>(); // Wave A per-round host notes

    /// The host's private note for the current round (null if none) — cockpit-only.
    public string? CurrentRoundNote =>
        Current is not null && RoundIndex >= 0 && RoundIndex < RoundNotes.Count && RoundNotes[RoundIndex].Length > 0
            ? RoundNotes[RoundIndex] : null;
    public string? Sponsor { get; set; }    // Wave D sponsor kit (big-screen footer)
    public string? BrandHex { get; set; }    // Wave D white-label accent (big-screen)
    public string? LeadCaptureUrl { get; set; } // Wave D lead-capture QR (final standings)
    public string? FastestUid { get; private set; }
    public bool Locked { get; private set; }
    public int? HostChoice { get; private set; }
    public bool HostAnswered => HostChoice is not null;

    private List<string> _shuffledOrder = new();
    private List<string> _shuffledValues = new();
    private long? _deadline; // epoch-ms answer deadline (live countdown, 3.23)

    private static long NowMs() => System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

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
    // In-room paper teams (3.29) — not networked; scored by the host and ranked
    // alongside the phone teams in ONE standings (the hybrid differentiator).
    private readonly Dictionary<string, string> _paperNames = new();
    private readonly Dictionary<string, int> _paperScores = new();
    private static bool IsPaper(string uid) => uid.StartsWith("paper:", StringComparison.Ordinal);

    public void AddPaperTeam(string name)
    {
        var n = name.Trim();
        if (n.Length == 0) return;
        var uid = "paper:" + Guid.NewGuid().ToString("N")[..8];
        _paperNames[uid] = n;
        _paperScores[uid] = 0;
        Notify();
    }

    /// Networked phone teams + in-room paper teams, ranked together.
    public IReadOnlyList<LiveHostNet.Joined> Standings
    {
        get
        {
            var net = Net.JoinedList();
            if (_paperScores.Count == 0) return net;
            var paper = _paperScores.Select(kv => new LiveHostNet.Joined(kv.Key, _paperNames[kv.Key], kv.Value));
            return net.Concat(paper)
                .OrderByDescending(j => j.Score).ThenBy(j => j.Name, StringComparer.Ordinal).ToList();
        }
    }
    public int PlayerCount => Net.PlayerCount;
    public int AnsweredCount => Net.AnsweredCount;
    public int RoundIndex => Current?.RoundIndex ?? 0;
    public bool IsWagerRound => WagerRoundIndex is { } w && Current is not null && RoundIndex == w;
    public int RoundNumber => RoundIndex + 1;
    public int RoundCount => Math.Max(_plan.Rounds.Count, 1);
    public string RoundTitle => RoundIndex < _plan.Rounds.Count ? _plan.Rounds[RoundIndex].Kind.NightRoundTitle() : "";

    private readonly HashSet<string> _hidden = new(); // moderation gate (3.26)

    public bool IsHidden(string uid) => _hidden.Contains(uid);

    /// Toggle a team's name off (or back on) the big screen — for an offensive
    /// networked name. The cockpit still shows the real name; the projector uses
    /// ModeratedStandings.
    public void ToggleHidden(string uid)
    {
        if (string.IsNullOrEmpty(uid)) return;
        if (!_hidden.Add(uid)) _hidden.Remove(uid);
        Notify();
    }

    /// Free-text review (3.21): on reveal of a Name-It round, each team's typed
    /// answer + whether the auto-scorer accepted it. The host can accept a
    /// borderline spelling the matcher rejected.
    public IReadOnlyList<TextReviewRow> TextReview
    {
        get
        {
            if (!Revealed || Current?.Accepted is not { } acc)
                return System.Array.Empty<TextReviewRow>();
            var names = Net.JoinedList().ToDictionary(j => j.Id, j => j.Name);
            return Net.AnswersSnapshot()
                .Where(kv => kv.Value.Text is not null)
                .Select(kv => new TextReviewRow(
                    kv.Key, names.GetValueOrDefault(kv.Key, "?"), kv.Value.Text!,
                    Store.GameEngine.MatchesAccepted(kv.Value.Text!, acc)))
                .OrderBy(r => r.AutoCorrect).ThenBy(r => r.Name, System.StringComparer.Ordinal)
                .ToList();
        }
    }

    /// Accept a team's free-text answer the auto-scorer rejected — award the
    /// per-correct points.
    public Task AcceptText(string uid) => AdjustScore(uid, PointsPerCorrect);

    /// Teams sharing the top score (a tie for first) — else empty (3.24).
    public IReadOnlyList<LiveHostNet.Joined> TiedLeaders => Ties(Standings);
    public bool HasTie => TiedLeaders.Count >= 2;

    /// Pure: the leaders sharing the (non-zero) top score, or empty if no tie.
    public static IReadOnlyList<LiveHostNet.Joined> Ties(IReadOnlyList<LiveHostNet.Joined> standings)
    {
        if (standings.Count < 2 || standings[0].Score == 0) return System.Array.Empty<LiveHostNet.Joined>();
        var top = standings[0].Score;
        var tied = standings.Where(j => j.Score == top).ToList();
        return tied.Count >= 2 ? tied : System.Array.Empty<LiveHostNet.Joined>();
    }

    /// Break a tie in the winner's favor (brains-only manual pick) — +1 to the
    /// chosen team so they're strictly ahead.
    public Task BreakTie(string uid) => AdjustScore(uid, +1);

    /// Merge one team into another (3.25) — combine their scores onto `intoUid`,
    /// zero the merged team, and drop it from the big screen. For a paper team that
    /// got split across two entries.
    public async Task MergeTeams(string intoUid, string fromUid)
    {
        if (string.IsNullOrEmpty(intoUid) || string.IsNullOrEmpty(fromUid) || intoUid == fromUid) return;
        await Net.SetScore(intoUid, Net.ScoreOf(intoUid) + Net.ScoreOf(fromUid));
        await Net.SetScore(fromUid, 0);
        _hidden.Add(fromUid);
        Notify();
    }

    /// Standings with hidden team names replaced by "(hidden)" — projector-safe.
    public IReadOnlyList<LiveHostNet.Joined> ModeratedStandings =>
        Standings.Select(j => _hidden.Contains(j.Id) ? j with { Name = "(hidden)" } : j).ToList();

    /// Teams flagged for leaving the app mid-question (Wave C cheat signal, 3.27).
    public int FlaggedCount => Net.AnswersSnapshot().Values.Count(a => a.Blurred == true);
    public bool HasFlags => FlaggedCount > 0;

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
        Revealed = false; HostChoice = null; Locked = false; _deadline = null;
        Index++;
        if (Current is null) await End();
        else { PrepareQuestion(); await Net.Publish(BuildPub()); }
        Notify();
    }

    /// Skip the current question without revealing or scoring it (show-nav 3.17).
    public async Task SkipNext()
    {
        if (CurrentStage != Stage.Playing) return;
        Revealed = false; HostChoice = null; Locked = false; _deadline = null;
        Index++;
        if (Current is null) await End();
        else { PrepareQuestion(); await Net.Publish(BuildPub()); }
        Notify();
    }

    /// Step back to the previous question (unrevealed) — for a misfire or a re-ask.
    public async Task GoBack()
    {
        if (CurrentStage != Stage.Playing || Index <= 0) return;
        Revealed = false; HostChoice = null; Locked = false; _deadline = null;
        Index--;
        PrepareQuestion();
        await Net.Publish(BuildPub());
        Notify();
    }

    public bool CanGoBack => CurrentStage == Stage.Playing && Index > 0;

    /// Live countdown (3.23) — the host starts/extends a per-question answer
    /// deadline, published so join clients + the projector tick it down.
    public async Task StartTimer(int seconds)
    {
        if (CurrentStage != Stage.Playing || Revealed || seconds <= 0) return;
        _deadline = NowMs() + seconds * 1000L;
        await Net.Publish(BuildPub());
        Notify();
    }

    public async Task AddTime(int seconds)
    {
        if (CurrentStage != Stage.Playing || Revealed) return;
        _deadline = (_deadline ?? NowMs()) + seconds * 1000L;
        await Net.Publish(BuildPub());
        Notify();
    }

    public async Task ClearTimer()
    {
        if (_deadline is null) return;
        _deadline = null;
        await Net.Publish(BuildPub());
        Notify();
    }

    /// Seconds left on the current deadline, or null when no timer is running.
    public int? SecondsRemaining => _deadline is { } d && !Revealed
        ? (int)System.Math.Max(0, (d - NowMs()) / 1000)
        : null;

    /// Manual score override (3.18) — nudge a team's score (never below 0).
    public async Task AdjustScore(string uid, int delta)
    {
        if (string.IsNullOrEmpty(uid)) return;
        if (IsPaper(uid))
        {
            if (_paperScores.ContainsKey(uid)) _paperScores[uid] = Math.Max(0, _paperScores[uid] + delta);
            Notify();
            return;
        }
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
            Deadline = Revealed ? null : _deadline,
            Wager = IsWagerRound ? true : null,
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

        // Final wager round: correct +stake, wrong −stake (clamped ≥0), no speed bonus.
        if (IsWagerRound)
        {
            foreach (var kv in answers)
            {
                var correct = LiveScoring.Score(q, kv.Value, _shuffledOrder, _shuffledValues, PointsPerCorrect) > 0;
                var stake = kv.Value.Wager ?? 0;
                var delta = LiveScoring.WagerDelta(correct, stake);
                if (delta != 0) await Net.SetScore(kv.Key, Math.Max(0, Net.ScoreOf(kv.Key) + delta));
            }
            return;
        }

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

/// One team's free-text submission under review (3.21).
public sealed record TextReviewRow(string Uid, string Name, string Text, bool AutoCorrect);
