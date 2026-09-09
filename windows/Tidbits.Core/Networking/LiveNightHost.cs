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
    /// 3.59: per-question overrides from the builder (index-aligned per round, 0 = default).
    public IReadOnlyList<IReadOnlyList<int>> QuestionTimers { get; set; } = new List<IReadOnlyList<int>>();
    public IReadOnlyList<IReadOnlyList<int>> QuestionPoints { get; set; } = new List<IReadOnlyList<int>>();
    private int PositionInRound => Current?.RoundIndex is int ri ? Questions.Take(Index).Count(x => x.RoundIndex == ri) : 0;
    public int? CurrentQuestionTimer => Current?.RoundIndex is int ri ? LiveEvent.Override(QuestionTimers, ri, PositionInRound) : null;
    public int? CurrentQuestionPoints => Current?.RoundIndex is int ri ? LiveEvent.Override(QuestionPoints, ri, PositionInRound) : null;
    /// What a correct answer is worth right now — the question's override, else the night's setting.
    public int CurrentPoints => CurrentQuestionPoints ?? PointsPerCorrect;
    /// 3.56: what the room has heard — corpus draws skip it, and every question
    /// this night shows is written to it. Null in tests that never host.
    public Store.PlayedLog? Played { get; set; }
    /// Teams the host accepted by hand on this question (3.21): the row says
    /// "Accepted" instead of offering the button again, and "accept from
    /// everyone" never pays one of them twice. Cleared per question.
    public HashSet<string> ManuallyAccepted { get; } = new();

    /// Points DEDUCTED for a wrong answer, 0 = off (the default, and what every
    /// night so far has played under). QuizXpress offers this and pub hosts use it
    /// to stop blind guessing on a four-option question — COMPETITOR-SCAN G3. Only
    /// a team that ANSWERED can lose points: staying silent is declining to guess,
    /// not being wrong, and penalising it would punish a table whose phone died.
    /// Matches macOS `LiveHostSession.wrongAnswerPenalty`.
    public int WrongAnswerPenalty { get; set; }
    public bool HostPlays { get; set; }
    public string HostName { get; set; } = "Host";
    public bool SpeedBonus { get; set; }
    public int? WagerRoundIndex { get; set; } // Wave A: which round is the final wager (RoundIndex), null = none
    public IReadOnlyList<string> RoundNotes { get; set; } = new List<string>(); // Wave A per-round host notes
    public IReadOnlyList<int> RoundTimers { get; set; } = new List<int>();      // Wave A per-round countdown (0 = untimed)
    /// The host's AUTHORED questions per round (index-aligned with the plan). A round
    /// with an empty list still comes from the corpus, so a half-authored event works.
    /// Without this the question editor would be theatre: the host edits a question,
    /// hits Host, and the night pulls a fresh corpus round over the top of their work.
    public IReadOnlyList<IReadOnlyList<Question>> AuthoredQuestions { get; set; } = new List<IReadOnlyList<Question>>();
    /// The media clip attached to each authored question, index-aligned with
    /// AuthoredQuestions. Without this the builder's audio/video round would author
    /// clips the cockpit never sees — the same "looks complete, plays silence"
    /// failure the macOS build shipped.
    public IReadOnlyList<IReadOnlyList<string>> AuthoredClips { get; set; } = new List<IReadOnlyList<string>>();

    /// The clip for the question now on screen, or null. Checks the file still
    /// exists, so the cockpit can show "clip unavailable" rather than a play
    /// control that does nothing.
    public string? CurrentClipPath
    {
        get
        {
            var q = Current;
            if (q?.RoundIndex is not int ri || ri < 0 || ri >= AuthoredClips.Count) return null;
            // Position WITHIN the round — the clip list is per-round, not per-night.
            int pos = Questions.Take(Index).Count(x => x.RoundIndex == ri);
            var clips = AuthoredClips[ri];
            if (pos < 0 || pos >= clips.Count) return null;
            var path = clips[pos];
            return string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path) ? null : path;
        }
    }

    /// Decision 060: the current question's clip as the ROOM is given it, set once
    /// the room node is in place; null until then and on a question without one.
    public LiveRoom.Media? CurrentMedia { get; private set; }
    /// What the cockpit says under the Play button about the phones.
    public string? MediaNote { get; private set; }
    /// Epoch ms of the host's Play, published so phones ready and position the clip.
    public long? MediaStartedAt { get; private set; }
    /// Decision 060 (pictures): the current question's picture node once it is in
    /// the room; null until then (the small fallback in `imageURL` shows).
    public LiveRoom.Media? CurrentPicture { get; private set; }

    private async Task SyncPicture()
    {
        var q = Current; if (q?.ImageUrl is null) return;
        var index = Index;
        var pic = await Task.Run(() => LiveMediaStore.PublishPicture(q.ImageUrl));
        if (Index != index || pic.Id is null || pic.Node is null || pic.Wire is null) return;
        if (!await Net.PublishMedia(pic.Id, pic.Node)) return;
        if (Index != index) return;
        CurrentPicture = pic.Wire;
        await Net.Publish(BuildPub());
        Notify();
    }

    /// Offer the current question's clip to the phones: prepare it, write the node
    /// BEFORE the pub that references it, and never publish over a question the
    /// host has already left.
    public async Task SyncMedia()
    {
        await SyncPicture();
        var path = CurrentClipPath;
        if (path is null) return;
        var index = Index;
        var prepared = await Task.Run(() => LiveClipPublisher.Prepare(path));
        if (Index != index) return;
        MediaNote = prepared.Note;
        if (prepared.Media is null) { Notify(); return; }
        if (prepared.Id is not null && prepared.Node is not null)
        {
            if (!await Net.PublishMedia(prepared.Id, prepared.Node)) { MediaNote = "Not on phones — the room refused the clip"; Notify(); return; }
        }
        if (Index != index) return;
        CurrentMedia = prepared.Media;
        await Net.Publish(BuildPub());
        Notify();
    }

    /// The host pressed Play: tell the phones when, so each readies the clip and
    /// positions it where the room is.
    public async Task CueMedia()
    {
        if (CurrentMedia is null) return;
        MediaStartedAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        await Net.Publish(BuildPub());
        Notify();
    }

    private async Task PublishCurrent()
    {
        await Net.Publish(BuildPub());
        await SyncMedia();
    }

    /// True when the current round HAS clips but this question's is gone — the
    /// difference between "no clip round" and "your clip moved", which the host
    /// needs to tell apart mid-night.
    public bool CurrentClipMissing
    {
        get
        {
            if (Current?.RoundIndex is not int ri || ri < 0 || ri >= AuthoredClips.Count) return false;
            return AuthoredClips[ri].Any(c => !string.IsNullOrWhiteSpace(c)) && CurrentClipPath is null;
        }
    }

    /// The authored countdown for the round now on screen, or 0 when untimed.
    public int RoundTimerSeconds =>
        RoundIndex >= 0 && RoundIndex < RoundTimers.Count ? RoundTimers[RoundIndex] : 0;

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
            // G7: one row per TEAM. JoinedList() is per DEVICE, so a table that
            // grouped appeared as three near-identical rows splitting its score.
            var net = Net.JoinedTeams().Where(j => !_removed.Contains(j.Id));
            var paper = _paperScores.Where(kv => !_removed.Contains(kv.Key))
                .Select(kv => new LiveHostNet.Joined(kv.Key, _paperNames[kv.Key], kv.Value));
            return net.Concat(paper)
                .OrderByDescending(j => j.Score).ThenBy(j => j.Name, StringComparer.Ordinal).ToList();
        }
    }
    public int PlayerCount => Net.PlayerCount;
    public int AnsweredCount => Net.AnsweredTeamCount;
    public int RoundIndex => Current?.RoundIndex ?? 0;
    public bool IsWagerRound => WagerRoundIndex is { } w && Current is not null && RoundIndex == w;

    /// G1: which rounds are buzz rounds (index-aligned, from the event).
    public IReadOnlyList<bool> BuzzRounds { get; set; } = new List<bool>();
    public bool IsBuzzRound => Current is not null && RoundIndex >= 0
                               && RoundIndex < BuzzRounds.Count && BuzzRounds[RoundIndex];

    /// G5: the pick-a-category grid of each round (index-aligned; null = an
    /// ordinary round). Mutable, because cells are marked taken as they are
    /// played — the grid the projector draws and the question the host reads must
    /// be the same object or they drift apart mid-round. Mirrors Swift
    /// `LiveRound.board`.
    public IReadOnlyList<LiveBoard?> RoundBoards { get; set; } = new List<LiveBoard?>();
    public LiveBoard? CurrentBoard =>
        RoundIndex >= 0 && RoundIndex < RoundBoards.Count ? RoundBoards[RoundIndex] : null;
    public bool IsBoardRound => CurrentBoard is not null;

    /// G5: hold the big screen on the grid, between questions of a board round.
    /// The room cannot pick a cell it cannot see, so this is a real phase.
    public bool ShowBoard { get; set; }
    /// G5: the team whose turn it is to pick (null = anyone / not a board round).
    public string? BoardChooser { get; set; }

    /// G5: the room picked a cell — play it. Returns false when the cell is
    /// missing or ALREADY taken, which is what a second click on one tile is; the
    /// caller must not advance on that. Mirrors Swift `pickBoardCell`.
    public bool PickBoardCell(string categoryId, int tier)
    {
        var board = CurrentBoard;
        if (board is null) return false;
        var cell = board.Cell(categoryId, tier);
        if (cell is null || cell.Taken) return false;
        if (!board.Take(categoryId, tier)) return false;
        var target = Questions.FindIndex(q => q.Id == cell.QuestionId);
        if (target < 0) return false;
        Index = target;
        Revealed = false;
        HostChoice = null;
        Locked = false;
        ShowBoard = false;
        PrepareQuestion();
        ArmRoundTimer();
        return true;
    }

    /// G5: pick a cell AND publish it, the way Next() does. A pick that changes
    /// the host's screen but not the phones is a question the room cannot answer.
    public async Task<bool> PickBoardCellAsync(string categoryId, int tier)
    {
        if (CurrentStage != Stage.Playing) return false;
        if (!PickBoardCell(categoryId, tier)) return false;
        await PublishCurrent();
        Notify();
        return true;
    }

    /// G5: back to the grid for the next pick.
    public void ReturnToBoard()
    {
        Revealed = false;
        ShowBoard = true;
    }

    /// The team that buzzed FIRST, or null if nobody has.
    ///
    /// Ranked by the SERVER stamp (`OrderKey`), never the handset clock — a buzzer
    /// decided by whose phone runs fast is not a buzzer. Mirrors Swift
    /// `LiveHostSession.firstBuzz`.
    /// `excluding` are teams that already buzzed and got it WRONG. A wrong buzz
    /// reopens the question to the rest of the room rather than ending it — that is
    /// what makes it a pub buzzer and not a single-shot lockout.
    public static string? FirstBuzz(IReadOnlyDictionary<string, LiveRoom.Answer> answers,
                                    IReadOnlySet<string>? excluding = null)
    {
        string? best = null; long bestKey = long.MaxValue;
        foreach (var kv in answers)
        {
            if (excluding is not null && excluding.Contains(kv.Key)) continue;
            if (kv.Value.OrderKey < bestKey) { bestKey = kv.Value.OrderKey; best = kv.Key; }
        }
        return best;
    }
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
                    Store.GameEngine.MatchesAccepted(kv.Value.Text!, acc), ManuallyAccepted.Contains(kv.Key)))
                .OrderBy(r => r.AutoCorrect).ThenBy(r => r.Name, System.StringComparer.Ordinal)
                .ToList();
        }
    }

    /// Accept a team's free-text answer the auto-scorer rejected — award the
    /// per-correct points, once.
    public async Task AcceptText(string uid)
    {
        if (string.IsNullOrEmpty(uid) || !ManuallyAccepted.Add(uid)) return;
        await AdjustScore(uid, CurrentPoints);
    }

    /// "Accept this answer from everyone" (3.21): the ruling joins the question's
    /// accepted list — every row that typed it turns correct and stays that way,
    /// and the pack carries the fix if it is saved — and each team the scorer had
    /// refused for that answer is paid once. Same team-dedup as the reveal scorer.
    public async Task AcceptTextForAll(string text)
    {
        if (Current is not { Accepted: { } acc } q) return;
        var t = text.Trim();
        if (t.Length == 0) return;
        var answers = Net.AnswersSnapshot();
        var scorable = LiveTeamRoster.ScorableUids(Net.Members(), answers.ToDictionary(kv => kv.Key, kv => kv.Value.OrderKey));
        var uids = TypedAlike(t, answers.Where(kv => scorable.Contains(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value), acc, ManuallyAccepted);
        if (!Store.GameEngine.MatchesAccepted(t, acc)) Questions[Index] = q with { Accepted = acc.Append(t).ToList() };
        foreach (var uid in uids) { ManuallyAccepted.Add(uid); await AdjustScore(uid, CurrentPoints); }
        Notify();
    }

    /// The uids whose typed answer IS `text` under the scorer's own normalisation
    /// and whom the scorer did not credit; `already` are the manual accepts so far.
    /// Mirrors Swift's LiveNightHost.typedAlike.
    public static IReadOnlyList<string> TypedAlike(string text, IReadOnlyDictionary<string, LiveRoom.Answer> answers,
                                                   IReadOnlyList<string> accepted, IReadOnlySet<string> already)
    {
        var n = Store.GameEngine.NormalizeType(text);
        if (n.Length == 0) return System.Array.Empty<string>();
        return answers
            .Where(kv => kv.Value.Text is { } t && !already.Contains(kv.Key)
                         && Store.GameEngine.NormalizeType(t) == n && !Store.GameEngine.MatchesAccepted(t, accepted))
            .Select(kv => kv.Key).OrderBy(u => u, System.StringComparer.Ordinal).ToList();
    }

    /// The round format of the question on screen (for the editor dialog).
    public GameMode CurrentKind => RoundIndex < _plan.Rounds.Count ? _plan.Rounds[RoundIndex].Kind : GameMode.Classic;

    /// 3.55 — a mid-night edit of the question on screen. The night's own copy
    /// changes (print/export carry the fix), the display shuffles are redone only
    /// when the shuffled content changed (a typo fix must not re-deal an ordering
    /// the room is halfway through), and the room is republished.
    public async Task ReplaceCurrent(Question q)
    {
        if (Current is not { } old) return;
        var next = q with { RoundIndex = old.RoundIndex };
        Questions[Index] = next;
        if (!SameList(old.Ordering, next.Ordering))
            _shuffledOrder = next.Ordering is { } o ? QueryHelpers.Shuffle(o.ToList()) : new();
        if (!SameList(old.Matching?.Values, next.Matching?.Values) || !SameList(old.Matching?.Keys, next.Matching?.Keys))
            _shuffledValues = next.Matching is { } m ? QueryHelpers.Shuffle(m.Values.ToList()) : new();
        await PublishCurrent();
        Notify();
    }

    private static bool SameList(IReadOnlyList<string>? a, IReadOnlyList<string>? b) =>
        a is null ? b is null : b is not null && a.SequenceEqual(b);

    /// Put an editor's clip decision onto the current question's seat in its
    /// round (the clip list is per-round, index-parallel), and re-offer the media.
    public async Task SetCurrentClip(string? path)
    {
        if (Current?.RoundIndex is not int ri || ri < 0) return;
        int pos = Questions.Take(Index).Count(x => x.RoundIndex == ri);
        var rounds = AuthoredClips.Select(r => r.ToList()).ToList();
        while (rounds.Count <= ri) rounds.Add(new List<string>());
        while (rounds[ri].Count <= pos) rounds[ri].Add("");
        rounds[ri][pos] = path ?? "";
        AuthoredClips = rounds;
        CurrentMedia = null; MediaNote = null; MediaStartedAt = null;
        await PublishCurrent();
        Notify();
    }

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

    /// 3.58 (A3.5): the closest guess to `target` wins the tie-break (+1) — the
    /// pub-standard "nearest wins" protocol. Mirrors the Mac's `breakTie`.
    public static string? ClosestWinner(double target, IReadOnlyDictionary<string, double> guesses) =>
        guesses.Count == 0 ? null
            : guesses.OrderBy(kv => Math.Abs(kv.Value - target)).ThenBy(kv => kv.Key, StringComparer.Ordinal).First().Key;
    public async Task BreakTieClosest(double target, IReadOnlyDictionary<string, double> guesses)
    {
        if (ClosestWinner(target, guesses) is { } winner) await AdjustScore(winner, +1);
    }

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

    /// Drop a team from the night entirely (macOS `session.removeTeam`) — the fix for a
    /// duplicate join or a team that walked out. Zeroes the score and hides the row, which is
    /// the same shape [MergeTeams] uses: the RTDB node is SHARED with that player's client, so
    /// deleting it outright would strand them mid-night rather than simply un-scoring them.
    public async Task RemoveTeam(string uid)
    {
        if (string.IsNullOrEmpty(uid)) return;
        await Net.SetScore(uid, 0);
        _removed.Add(uid);
        _hidden.Add(uid);
        Notify();
    }

    private readonly HashSet<string> _removed = new();

    /// Teams the host dropped — excluded from standings, the projector and the CSV export.
    public bool IsRemoved(string uid) => _removed.Contains(uid);

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

    /// Load the night's questions WITHOUT opening a room.
    ///
    /// `Start()` opens an RTDB room before it can build questions, so nothing could
    /// exercise the clip/question wiring without a network. This is the same build,
    /// stopping short of the room — used by tests and safe for a dry run.
    public async Task LoadQuestionsOffline()
    {
        Questions = await BuildNightQuestions();
        if (Questions.Count == 0) return;
        // Enter PLAYING as well. Without this the offline build left the stage in
        // Lobby, so a rendered projector showed the JOIN NOW splash no matter what
        // was loaded — which meant a snapshot test could assert "nothing on the big
        // screen is truncated" and pass because there was no question on the big
        // screen at all. An assertion that cannot fire is not an assertion.
        Index = 0; Revealed = false; HostChoice = null; Locked = false;
        CurrentStage = Stage.Playing;
        PrepareQuestion();
    }

    /// The same question build, without a room — for "Preview solo" and for tests.
    /// Shares one implementation with the live path so a preview can never vet a
    /// different night than the one the room plays.
    public static async Task<List<Question>> PreviewQuestions(
        NightPlan plan, LiveEvent ev, QuestionProvider provider, TriviaCategory category)
    {
        var host = new LiveNightHost(plan, category, provider, ev.Name)
        {
            AuthoredQuestions = Enumerable.Range(0, plan.Rounds.Count).Select(ev.QuestionsFor).ToList(),
        };
        return await host.BuildNightQuestions();
    }

    /// The night's questions: the host's authored ones where they exist, the corpus
    /// everywhere else. Rounds are still pulled in ONE provider call so its
    /// already-seen de-duplication holds across the corpus-sourced rounds.
    internal async Task<List<Question>> BuildNightQuestions()
    {
        // 3.56: a sourced round never re-asks what an earlier night showed — the
        // provider's own seen set is per launch; the log outlives it.
        if (Played is { } played) _provider.MarkSeen(played.Ids);
        bool anyAuthored = _plan.Rounds
            .Select((_, i) => i < AuthoredQuestions.Count ? AuthoredQuestions[i].Count : 0)
            .Any(n => n > 0);
        if (!anyAuthored) return await _provider.NightQuestions(_plan, _category);

        // Ask the provider only for the rounds the host did NOT author, so an event
        // that is fully authored never touches the corpus at all (and works offline).
        var sourcedPlan = new NightPlan
        {
            Rounds = _plan.Rounds
                .Select((r, i) => new NightRound
                {
                    Kind = r.Kind,
                    Count = (i < AuthoredQuestions.Count && AuthoredQuestions[i].Count > 0) ? 0 : r.Count,
                })
                .Where(r => r.Count > 0).ToList(),
        };
        var sourced = sourcedPlan.Rounds.Count > 0
            ? await _provider.NightQuestions(sourcedPlan, _category)
            : new List<Question>();

        var out_ = new List<Question>();
        int sourcedCursor = 0;
        for (int i = 0; i < _plan.Rounds.Count; i++)
        {
            var authored = i < AuthoredQuestions.Count ? AuthoredQuestions[i] : [];
            if (authored.Count > 0)
            {
                out_.AddRange(authored.Select(q => q with { RoundIndex = i }));
            }
            else
            {
                // The sourced list is round-tagged with ITS OWN indices, which are the
                // compacted ones — re-tag against the real plan position.
                int want = _plan.Rounds[i].Count;
                for (int k = 0; k < want && sourcedCursor < sourced.Count; k++, sourcedCursor++)
                    out_.Add(sourced[sourcedCursor] with { RoundIndex = i });
            }
        }
        return out_;
    }

    public async Task Start()
    {
        if (!Net.IsOpen) await OpenRoom();
        if (!Net.IsOpen) return;
        Questions = await BuildNightQuestions();
        if (Questions.Count == 0) { ErrorText = "No questions available."; Notify(); return; }
        if (HostPlays) await Net.JoinAsHost(string.IsNullOrEmpty(HostName) ? "Host" : HostName);
        Index = 0; Revealed = false; HostChoice = null; Locked = false; CurrentStage = Stage.Playing;
        PrepareQuestion();
        ArmRoundTimer();
        await Net.SetState("live");
        await PublishCurrent();
        Notify();
    }

    private void PrepareQuestion()
    {
        CurrentMedia = null; MediaNote = null; MediaStartedAt = null; CurrentPicture = null;   // Decision 060: offered when in place
        if (Current is { } shown) Played?.Record(new[] { shown.Id }, Title);   // 3.56: the room heard it
        ManuallyAccepted.Clear();
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
        else { PrepareQuestion(); ArmRoundTimer(); await PublishCurrent(); }
        Notify();
    }

    /// Skip the current question without revealing or scoring it (show-nav 3.17).
    public async Task SkipNext()
    {
        if (CurrentStage != Stage.Playing) return;
        Revealed = false; HostChoice = null; Locked = false; _deadline = null;
        Index++;
        if (Current is null) await End();
        else { PrepareQuestion(); ArmRoundTimer(); await PublishCurrent(); }
        Notify();
    }

    /// Step back to the previous question (unrevealed) — for a misfire or a re-ask.
    public async Task GoBack()
    {
        if (CurrentStage != Stage.Playing || Index <= 0) return;
        Revealed = false; HostChoice = null; Locked = false; _deadline = null;
        Index--;
        // No ArmRoundTimer here on purpose: going back means the host is fixing something,
        // and dropping a fresh countdown on a re-ask would rush the room mid-correction.
        PrepareQuestion();
        await PublishCurrent();
        Notify();
    }

    public bool CanGoBack => CurrentStage == Stage.Playing && Index > 0;

    /// Wave A: arm the countdown from the round the new question belongs to (0 = untimed,
    /// which leaves the deadline cleared so the host can still start one by hand). Set
    /// directly rather than via StartTimer so it costs no extra publish — the caller
    /// publishes the pub right after.
    private void ArmRoundTimer()
    {
        var secs = CurrentQuestionTimer ?? RoundTimerSeconds;
        _deadline = secs > 0 ? NowMs() + secs * 1000L : null;
    }

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
    /// The published state, for tests. What the joiners get IS the contract — a
    /// board phase that never reaches a phone is a room answering the wrong
    /// question — so it is asserted rather than inferred from the UI.
    public LiveRoom.Pub BuildPubForTesting() => BuildPub();

    private LiveRoom.Pub BuildPub()
    {

        // G5: while the grid is up there is NO live question. Publishing the
        // previous one leaves it on every phone with its answer buttons live,
        // so the room can answer a question that is no longer being asked.
        if (ShowBoard && CurrentBoard is { } b)
        {
            var cols = b.Categories.ToList();
            return new LiveRoom.Pub
            {
                Round = RoundNumber, RoundTitle = RoundTitle, Qid = $"board-{RoundNumber}",
                QNum = 0, QTotal = 0, Phase = LiveRoom.Phase.Board,
                Prompt = "Pick a category", Options = null, Format = "",
                Board = new LiveRoom.BoardPub
                {
                    Categories = cols.Select(c => TriviaCategory.Named(c).Name).ToList(),
                    Tiers = b.Tiers.ToList(),
                    Taken = b.Cells.Where(c => c.Taken)
                                    .Select(c => $"{cols.IndexOf(c.CategoryId)}:{c.Tier}")
                                    .Where(k => !k.StartsWith("-1")).ToList(),
                    Chooser = BoardChooser,
                    Remaining = b.Remaining.Count,
                    Points = b.PointsRemaining,
                },
            };
        }
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
            ImageUrl = LiveMediaStore.PublishPicture(q.ImageUrl).Fallback,   // §5.3: the https twin, or a SMALL data URL
            Picture = CurrentPicture,                                        // Decision 060: the full picture, once its node is in the room
            // The learning payoff, reveal only: the story and its Wikipedia source. The
            // Windows host had published neither — only its own projector showed the story.
            Story = Revealed && !string.IsNullOrWhiteSpace(q.Explanation) ? q.Explanation.Trim() : null,
            Source = Revealed && !string.IsNullOrWhiteSpace(q.SourceTitle) ? new LiveRoom.Source { Title = q.SourceTitle.Trim(), Url = q.SourceUrl } : null,
            Numeric = q.Closest is { } c ? new LiveRoom.Numeric { Min = c.Min, Max = c.Max, Step = c.Step, Unit = c.Unit } : null,
            OrderItems = q.Ordering is not null ? _shuffledOrder : null,
            MatchKeys = q.Matching?.Keys,
            MatchValues = q.Matching is not null ? _shuffledValues : null,
            EnumTarget = q.Enumerate?.Total,
            Locked = Locked && !Revealed ? true : null,
            Deadline = Revealed ? null : _deadline,
            Wager = IsWagerRound ? true : null,
            Buzz = IsBuzzRound ? true : null,          // G1: joiners show a BUZZ button
            Media = CurrentMedia is { } m ? m with { StartedAt = MediaStartedAt } : null,   // Decision 060
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
                var correct = LiveScoring.Score(q, kv.Value, _shuffledOrder, _shuffledValues, CurrentPoints) > 0;
                var stake = kv.Value.Wager ?? 0;
                var delta = LiveScoring.WagerDelta(correct, stake);
                if (delta != 0) await Net.SetScore(kv.Key, Math.Max(0, Net.ScoreOf(kv.Key) + delta));
            }
            return;
        }

        // G7: exactly one answer per TEAM reaches the scoreboard. Walking the
        // answers per uid is correct while a device IS a team, and awards a table
        // twice the moment two of its phones answer — or penalises it twice under
        // negative marking. Mirrors the Swift scoreReveal filter.
        var scorable = LiveTeamRoster.ScorableUids(
            Net.Members(), answers.ToDictionary(kv => kv.Key, kv => kv.Value.OrderKey));

        var baseScores = answers.Where(kv => scorable.Contains(kv.Key)).Select(kv =>
            (uid: kv.Key, pts: LiveScoring.Score(q, kv.Value, _shuffledOrder, _shuffledValues, CurrentPoints), ts: kv.Value.OrderKey)).ToList();

        var correctBySpeed = baseScores.Where(e => e.pts > 0).OrderBy(e => e.ts).ToList();
        FastestUid = correctBySpeed.Count > 0 ? correctBySpeed[0].uid : null;

        var bonus = SpeedBonus
            ? LiveScoring.SpeedBonuses(correctBySpeed.Select(e => e.uid))
            : new Dictionary<string, int>();

        foreach (var e in baseScores)
        {
            var total = e.pts + bonus.GetValueOrDefault(e.uid);
            if (total > 0) await Net.SetScore(e.uid, Net.ScoreOf(e.uid) + total);
            // G3: negative marking. `baseScores` is built from ANSWERS, so a team
            // that submitted nothing is not in this loop at all — which is exactly
            // the rule (silence is not a wrong answer).
            else if (WrongAnswerPenalty > 0)
                await Net.SetScore(e.uid, Net.ScoreOf(e.uid) - WrongAnswerPenalty);
        }
    }
}

/// One team's free-text submission under review (3.21).
public sealed record TextReviewRow(string Uid, string Name, string Text, bool AutoCorrect, bool Accepted = false);
