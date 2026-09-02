using System.Linq;
using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Networking;

namespace Tidbits.App.ViewModels;

/// One climbing-leaderboard row for the big screen (rank + gold-leader accent).
public sealed record LiveStandingRow(int Rank, string Name, int Score, Avalonia.Media.IBrush RankColor);

/// Wraps a LiveNightHost for the cockpit UI. LiveNightHost relays its LiveHostNet
/// changes (which fire on background SSE threads); this marshals them to the UI
/// thread so bindings update safely.
public sealed class LiveHostViewModel : ObservableObject
{
    public LiveNightHost Host { get; }

    public LiveHostViewModel(LiveNightHost host)
    {
        Host = host;
        Host.PropertyChanged += (_, _) => Dispatcher.UIThread.Post(() => OnPropertyChanged(string.Empty));
    }

    public bool IsLobby => Host.CurrentStage == LiveNightHost.Stage.Lobby;
    public bool IsPlaying => Host.CurrentStage == LiveNightHost.Stage.Playing;
    public bool IsEnded => Host.CurrentStage == LiveNightHost.Stage.Ended;
    public bool IsReveal => Host.Revealed;
    public bool IsWagerRound => Host.IsWagerRound;

    // Big-screen standings hold (3.39) — the host parks the current climbing
    // leaderboard on the projector between rounds; the question view yields to it.
    private bool _holdStandings;
    public bool HoldStandings
    {
        get => _holdStandings;
        private set { _holdStandings = value; OnPropertyChanged(nameof(HoldStandings)); OnPropertyChanged(nameof(ShowBigScreenStandings)); OnPropertyChanged(nameof(ShowQuestionScreen)); }
    }
    public bool ShowBigScreenStandings => IsPlaying && HoldStandings;

    /// "SCORES AFTER ROUND 2", not a bare "STANDINGS". A host reading the scores
    /// out says which round they are for, and the Mac projector names it — this is
    /// the same slide on both desktops (COMPETITOR-SCAN G2).
    public string StandingsHeadline => $"SCORES AFTER ROUND {Host.RoundNumber}";

    /// The between-rounds slide with no teams was a TITLE OVER AN EMPTY SCREEN —
    /// the same blank wall the macOS final standings had. A host who holds the
    /// scores before anyone has joined, or who runs on paper without adding the
    /// teams, shows the room nothing and cannot tell whether it is broken.
    public bool HasNoStandings => RankedStandings.Count == 0;
    public bool ShowQuestionScreen => IsPlaying && !HoldStandings;
    // ---- G1 buzz round -------------------------------------------------------
    // Mirrors the Mac cockpit panel: name who buzzed, Correct awards and reveals,
    // Wrong rules them out and reopens the buzzer to the rest of the room.

    private readonly System.Collections.Generic.HashSet<string> _buzzedOut = new();

    /// The uid holding the buzzer, or null if nobody has buzzed (or everyone who
    /// has was already ruled out).
    public string? BuzzUid => Host.IsBuzzRound && !Host.Revealed
        ? LiveNightHost.FirstBuzz(Host.Net.AnswersSnapshot(), _buzzedOut)
        : null;

    public bool HasBuzz => BuzzUid is not null;

    /// "<team> buzzed" — the host needs the NAME, not a uid, to call on a table.
    public string BuzzLabel
    {
        get
        {
            var uid = BuzzUid;
            if (uid is null) return "";
            var name = Host.Net.JoinedList().FirstOrDefault(j => j.Id == uid).Name;
            return $"{(string.IsNullOrWhiteSpace(name) ? "Team" : name)} buzzed";
        }
    }

    public async Task BuzzCorrect()
    {
        if (BuzzUid is not { } uid) return;
        await Host.Net.SetScore(uid, Host.Net.ScoreOf(uid) + Host.PointsPerCorrect);
        await Host.Reveal();
        NotifyBuzz();
    }

    /// A wrong buzz REOPENS the question to the rest — it does not end it.
    public void BuzzWrong()
    {
        if (BuzzUid is { } uid) _buzzedOut.Add(uid);
        NotifyBuzz();
    }

    /// Every new question reopens the buzzer to everyone.
    public void ClearBuzzedOut() { _buzzedOut.Clear(); NotifyBuzz(); }

    private void NotifyBuzz()
    {
        OnPropertyChanged(nameof(BuzzUid));
        OnPropertyChanged(nameof(HasBuzz));
        OnPropertyChanged(nameof(BuzzLabel));
    }

    public void ToggleHold() => HoldStandings = !HoldStandings;

    /// G3 negative marking, cycled 0 -> 1 -> 2 -> 0 from one control, because the
    /// cockpit is driven mid-show and a stepper is two targets to hit.
    public string PenaltyLabel => Host.WrongAnswerPenalty == 0
        ? "No penalty" : $"-{Host.WrongAnswerPenalty}/wrong";
    public void CyclePenalty()
    {
        Host.WrongAnswerPenalty = (Host.WrongAnswerPenalty + 1) % 3;
        OnPropertyChanged(nameof(PenaltyLabel));
    }

    /// Moderated standings with a 1-based rank + a gold accent for the leader — the
    /// climbing-leaderboard rows for the big screen.
    public System.Collections.Generic.IReadOnlyList<LiveStandingRow> RankedStandings =>
        Host.ModeratedStandings.Select((j, i) => new LiveStandingRow(
            i + 1, j.Name, j.Score,
            new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(i == 0 ? "#FFC93C" : "#FFFFFF")))).ToList();
    // Round-intro moment (3.40): the first question of a round gets a big title band.
    public bool ShowRoundIntro => !Host.Revealed && Host.QuestionInRound.N == 1;
    // Reveal choreography (3.38): the correct option index once revealed (else null).
    public int? RevealCorrectIndex => Host.Revealed && Host.Current is { } q ? q.CorrectIndex : null;
    public string? CurrentRoundNote => Host.CurrentRoundNote;
    /// The clip attached to the question on screen (audio/video round), or null.
    public string? CurrentClipPath => Host.CurrentClipPath;
    public bool HasClip => Host.CurrentClipPath is not null;
    /// The round HAS clips but this question's has moved or been deleted. Shown as
    /// an explicit warning rather than a play button that does nothing — a host
    /// discovers a dead control mid-round, with a room watching.
    public bool ClipMissing => Host.CurrentClipMissing;
    public string ClipName => Host.CurrentClipPath is { } p ? System.IO.Path.GetFileName(p) : "";
    public bool HasRoundNote => Host.CurrentRoundNote is not null;
    /// The correct option text (shown big on the projector at reveal).
    public string? RevealAnswer => Host.Current is { } q ? LiveScoring.AnswerLine(q) : null;
    /// The story/fact behind the answer, shown on the big screen at reveal (3.42) —
    /// parity with the join client's reveal card.
    public string? RevealStory => Host.Revealed && Host.Current is { Explanation.Length: > 0 } q ? q.Explanation : null;
    public bool HasRevealStory => RevealStory is not null;

    public bool CanGoBack => Host.CanGoBack;
    public int? SecondsRemaining => Host.SecondsRemaining;
    public bool HasFlags => Host.HasFlags;

    // Wave D venue branding (big screen).
    public bool HasLeadCapture => !string.IsNullOrWhiteSpace(Host.LeadCaptureUrl);
    public string? LeadCaptureUrl => Host.LeadCaptureUrl;
    public bool HasSponsor => !string.IsNullOrWhiteSpace(Host.Sponsor);
    public string SponsorLine => $"Brought to you by {Host.Sponsor}";
    public Avalonia.Media.IBrush BrandBrush
    {
        get
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(Host.BrandHex))
                    return new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(Host.BrandHex!));
            }
            catch { /* fall through to the brand default */ }
            return new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35"));
        }
    }
    public bool IsLocked => Host.Locked;
    /// The answer window has hit its deadline and isn't locked yet — cue auto-lock.
    public bool AutoLockDue => Host.SecondsRemaining == 0 && !Host.Locked && !Host.Revealed;
    public string FlagLine => Host.FlaggedCount == 1
        ? "1 team left the app this question"
        : $"{Host.FlaggedCount} teams left the app this question";

    /// Big-screen chrome (3.42): "Question X of Y · N players".
    public string QuestionChrome
    {
        get
        {
            var (n, of) = Host.QuestionInRound;
            var players = Host.PlayerCount;
            var chrome = $"Question {n} of {of} · {players} player{(players == 1 ? "" : "s")}";
            if (Host.Current is { } q) chrome += $" · {DifficultyLabel(q.Difficulty)}";
            return chrome;
        }
    }

    /// Coarse difficulty band for the big-screen chrome (1–2 easy, 3 medium, 4–5 hard).
    private static string DifficultyLabel(int d) => d <= 2 ? "Easy" : d == 3 ? "Medium" : "Hard";

    // Winner celebration (3.41) — top of the ordered standings.
    public bool HasWinner => Host.Standings.Count > 0;
    public string WinnerLine => Host.Standings.Count > 0 ? $"{Host.Standings[0].Name} wins the night" : "";

    public Task StartHosting() => Host.Start();
    public Task Reveal() => Host.Reveal();
    public Task Next() => Host.Next();
    public Task Lock() => Host.Lock();
    public Task Skip() => Host.SkipNext();
    public Task Back() => Host.GoBack();
    public Task StartTimer(int seconds) => Host.StartTimer(seconds);
    public Task AddTime(int seconds) => Host.AddTime(seconds);
    public Task ClearTimer() => Host.ClearTimer();
    public Task Adjust(string uid, int delta) => Host.AdjustScore(uid, delta);
    public Task Close() => Host.Close();

    /// The unified standings as CSV text (Wave C export).
    public string StandingsCsv() => LiveExport.StandingsCsv(Host.Standings);
    public bool HasStandings => Host.Standings.Count > 0;

    // Name moderation gate (3.26) — projector uses the moderated names.
    public System.Collections.Generic.IReadOnlyList<LiveHostNet.Joined> ModeratedStandings => Host.ModeratedStandings;
    public void ToggleHidden(string uid) => Host.ToggleHidden(uid);
    public bool IsHidden(string uid) => Host.IsHidden(uid);
    public Task MergeTeams(string intoUid, string fromUid) => Host.MergeTeams(intoUid, fromUid);
    public Task RemoveTeam(string uid) => Host.RemoveTeam(uid);   // drop a duplicate/departed team (macOS parity)
    public void AddPaperTeam(string name) => Host.AddPaperTeam(name); // in-room paper team (3.29)

    // Free-text review (3.21) — accept a borderline typed answer.
    public System.Collections.Generic.IReadOnlyList<TextReviewRow> TextReview => Host.TextReview;
    public Task AcceptText(string uid) => Host.AcceptText(uid);

    // Tie-break (3.24) — brains-only manual pick among the tied leaders.
    public bool HasTie => Host.HasTie;
    public System.Collections.Generic.IReadOnlyList<LiveHostNet.Joined> TiedLeaders => Host.TiedLeaders;
    public Task BreakTie(string uid) => Host.BreakTie(uid);
}
